import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import '../models/event_model.dart';
import '../screens/evenements/event_actor.dart';
import '../screens/evenements/event_rules.dart';
import '../screens/evenements/event_validators.dart';
import '../screens/evenements/location_service.dart';
import '../services/local_store.dart';
import '../services/storage_service.dart';

/// Erreur d'action sur un événement, avec un message prêt à afficher.
class EventActionException implements Exception {
  final String message;
  const EventActionException(this.message);

  @override
  String toString() => message;
}

/// Suppression refusée car l'événement a des inscrits : l'écran propose
/// alors d'annuler l'événement à la place.
class EventHasRegistrantsException extends EventActionException {
  const EventHasRegistrantsException(super.message);
}

/// Gestion des Événements : lecture, création, modification, annulation,
/// suppression, inscription, pointage et filtres.
///
/// Les événements sont stockés sur le téléphone ([LocalStore], collection
/// `events`) : tout fonctionne hors-ligne. Chaque action relit la version
/// enregistrée, vérifie les règles puis écrit, SANS `await` entre la lecture
/// et l'écriture : c'est atomique (rôle des anciennes transactions), deux
/// actions ne peuvent pas s'écraser.
///
/// Les règles que vérifiait le serveur sont vérifiées ICI, sur la version
/// enregistrée et avec l'identité de la session ([EventActor]), pas avec ce
/// que l'écran transmet : contenu valide à la création et à la modification,
/// organisateur = personne connectée, seul l'organisateur ou un admin
/// modifie / annule / supprime / pointe, chacun ne s'inscrit que lui-même.
class EventProvider extends ChangeNotifier {
  /// [store], [storage] et [actor] (personne connectée, lue par défaut dans
  /// la session enregistrée) remplaçables dans les tests.
  EventProvider({LocalStore? store, StorageService? storage, EventActor? Function()? actor})
      : _store = store ?? LocalStore(),
        _storage = storage ?? StorageService(),
        _actorOverride = actor;

  final LocalStore _store;
  final StorageService _storage;
  final EventActor? Function()? _actorOverride;
  static const _collection = AppConstants.eventsCollection;

  /// Personne connectée maintenant (null = visiteur).
  EventActor? get _actor => _actorOverride != null ? _actorOverride() : EventActor.fromStore(_store);

  EventActor _requireActor(String action) {
    final actor = _actor;
    if (actor == null) throw EventActionException('Connectez-vous pour $action.');
    return actor;
  }

  /// Seul l'organisateur de l'événement ou un admin peut [action].
  static void _requireManager(EventActor actor, EventModel event, String action) {
    if (!actor.canManage(event)) {
      throw EventActionException("Seul l'organisateur ou un admin peut $action.");
    }
  }

  /// Tous les événements enregistrés (pas seulement ceux chargés à l'écran).
  List<EventModel> _storedEvents() => [for (final d in _store.all(_collection)) EventModel.fromMap(d.id, d.data)];

  /// Réseau disponible : ne concerne plus les données (toujours locales),
  /// seulement les services web de la fiche et du formulaire (carte, météo,
  /// itinéraire, suggestions de lieu).
  bool _isOnline = true;
  bool get isOnline => _isOnline;
  void updateConnectivity(bool online) => _isOnline = online;

  /// Événements dont une inscription/désinscription est en cours d'écriture.
  final Set<String> _busyEventIds = {};
  bool isRegistrationBusy(String eventId) => _busyEventIds.contains(eventId);

  List<EventModel> _all = [];
  /// Tous les événements chargés (lecture seule), pour les contrôles du formulaire.
  List<EventModel> get all => List.unmodifiable(_all);
  bool isLoading = false;

  // ---------------------------------------------------------------- Filtres

  EventFilter filter = EventFilter.upcoming;
  String? categoryFilter;
  DateTime? selectedDay;
  PriceFilter priceFilter = PriceFilter.all;

  void setPriceFilter(PriceFilter value) {
    priceFilter = value;
    notifyListeners();
  }

  void setFilter(EventFilter value) {
    filter = value;
    notifyListeners();
  }

  void setCategoryFilter(String? category) {
    categoryFilter = category;
    notifyListeners();
  }

  void setSelectedDay(DateTime? day) {
    selectedDay = day;
    notifyListeners();
  }

  // --------------------------------------------------------- Près de moi

  /// Tri choisi. « Près de moi » ne s'applique qu'à l'onglet « À venir ».
  EventSort sort = EventSort.date;

  /// Position de l'utilisateur, lue UNE fois au choix du tri et gardée
  /// 5 minutes (pas à chaque reconstruction de l'écran).
  /// VIE PRIVÉE : cette position reste sur le téléphone ; elle sert
  /// seulement à calculer les distances localement, rien n'est envoyé.
  ({double lat, double lng})? _origin;
  DateTime? _originAt;
  bool locating = false;
  static const _originMaxAge = Duration(minutes: 5);

  /// Tri « Près de moi » réellement actif (onglet À venir + position connue).
  bool get isNearMeActive => sort == EventSort.nearMe && filter == EventFilter.upcoming && _origin != null;

  /// Distance (m) jusqu'à [event] quand « Près de moi » est actif, sinon null.
  double? distanceTo(EventModel event) => isNearMeActive ? EventRules.distanceMeters(event, _origin!) : null;

  void setSortByDate() {
    sort = EventSort.date;
    notifyListeners();
  }

  /// Active « Près de moi » : position du GPS (hors-ligne aussi : le GPS
  /// n'a pas besoin du réseau), ou celle de moins de 5 minutes. En cas
  /// d'échec, on revient au tri par date et on renvoie l'échec pour que
  /// l'écran l'explique.
  Future<PositionFailure?> enableNearMe() async {
    final fresh = _originAt != null && DateTime.now().difference(_originAt!) < _originMaxAge;
    if (_origin != null && fresh) {
      sort = EventSort.nearMe;
      notifyListeners();
      return null;
    }
    locating = true;
    notifyListeners();
    final response = await LocationService.currentPosition();
    locating = false;
    switch (response) {
      case PositionSuccess(:final position):
        _origin = (lat: position.latitude, lng: position.longitude);
        _originAt = DateTime.now();
        sort = EventSort.nearMe;
        notifyListeners();
        return null;
      case PositionFailure():
        sort = EventSort.date;
        notifyListeners();
        return response;
    }
  }

  /// Liste affichée : filtre principal + catégorie + jour + recherche + prix,
  /// triée par début, ou par distance si « Près de moi » est actif.
  List<EventModel> visibleEvents(String? userId, {String query = ''}) {
    final list = EventRules.filter(_all,
        filter: filter,
        now: DateTime.now(),
        userId: userId,
        category: categoryFilter,
        day: selectedDay,
        query: query,
        price: priceFilter);
    return isNearMeActive ? EventRules.sortByDistance(list, _origin!) : list;
  }

  /// Événements du calendrier : filtre principal + catégorie + prix, mais
  /// sans le jour (le calendrier montre tous les jours) ni la recherche.
  List<EventModel> calendarEvents(String? userId) => EventRules.filter(_all,
      filter: filter, now: DateTime.now(), userId: userId, category: categoryFilter, price: priceFilter);

  /// À venir (ni annulés ni terminés), filtrés par catégorie.
  List<EventModel> get upcoming =>
      EventRules.filter(_all, filter: EventFilter.upcoming, now: DateTime.now(), category: categoryFilter);

  /// À venir ce jour-là, en tenant compte de la catégorie, triés par début.
  List<EventModel> eventsOnDay(DateTime day) => EventRules.filter(_all,
      filter: EventFilter.upcoming, now: DateTime.now(), category: categoryFilter, day: day);

  List<EventModel> get publicPreview => upcoming.take(5).toList();

  /// Version la plus récente d'un événement (null s'il n'est plus chargé).
  EventModel? findById(String id) {
    for (final e in _all) {
      if (e.id == id) return e;
    }
    return null;
  }

  /// Message d'erreur du dernier chargement (null = OK).
  String? loadError;

  /// Lecture de tous les événements enregistrés sur le téléphone.
  Future<void> load() async {
    isLoading = true;
    loadError = null;
    notifyListeners();
    try {
      _all = [for (final d in _store.all(_collection)) EventModel.fromMap(d.id, d.data)];
    } catch (e) {
      debugPrint('Chargement des événements échoué : $e');
      loadError = 'Impossible de charger les événements. Réessayez.';
    }
    isLoading = false;
    notifyListeners();
  }

  /// Écoute en direct UN événement (règle 10) : sa version enregistrée
  /// maintenant, puis à chaque modification. Chaque nouvelle version met
  /// aussi à jour la copie du provider, pour que les actions (inscription…)
  /// partent des données les plus récentes. null : l'événement a été supprimé.
  Stream<EventModel?> watchEvent(String id) {
    return _store.watchDoc(_collection, id).map((data) {
      if (data == null) {
        if (findById(id) != null) {
          _all = _all.where((e) => e.id != id).toList();
          notifyListeners();
        }
        return null;
      }
      final event = EventModel.fromMap(id, data);
      if (findById(id) != null) _putLocal(event);
      return event;
    });
  }

  /// Remplace (ou ajoute) un événement dans la liste du provider.
  void _putLocal(EventModel updated) {
    final known = findById(updated.id) != null;
    _all = known ? [for (final e in _all) e.id == updated.id ? updated : e] : [..._all, updated];
    notifyListeners();
  }

  /// Version enregistrée de l'événement [id] ; si elle n'existe plus, on le
  /// retire de la liste et on lève une [EventActionException].
  EventModel _readStored(String id) {
    final data = _store.get(_collection, id);
    if (data == null) {
      if (findById(id) != null) {
        _all = _all.where((e) => e.id != id).toList();
        notifyListeners();
      }
      throw const EventActionException("Cet événement n'existe plus.");
    }
    return EventModel.fromMap(id, data);
  }

  /// Écrit puis relit l'événement [id] pour mettre à jour la liste. Une
  /// erreur de la base devient un message lisible.
  Future<EventModel> _write(String id, Future<void> Function() write) async {
    try {
      await write();
    } catch (e) {
      debugPrint('Écriture événement $id échouée : $e');
      throw const EventActionException("Impossible d'enregistrer. Réessayez.");
    }
    final saved = EventModel.fromMap(id, _store.get(_collection, id) ?? const {});
    _putLocal(saved);
    return saved;
  }

  // --------------------------------------------------------------- Création

  /// Création. [draft.id] est généré UNE fois à l'ouverture du formulaire :
  /// un nouvel essai avec le même id ne recrée rien (jamais de doublon) et
  /// garde la date de création du premier enregistrement.
  ///
  /// Vérifié ici, même si le formulaire est contourné : personne connectée
  /// et organisateur = elle ; contenu valide (titre, description, lieu,
  /// catégorie, dates, capacité, prix, coordonnées, affiche) ; début dans au
  /// moins 15 minutes ; événement neuf (actif, sans inscrits, présents ni
  /// payés) ; pas de doublon (même titre, même début) ; 5 créations par jour.
  Future<void> createEvent(EventModel draft) async {
    final actor = _requireActor('créer un événement');
    final now = DateTime.now();
    if (draft.organizerId != actor.uid) {
      throw const EventActionException("L'organisateur doit être la personne connectée.");
    }
    final existing = _store.get(_collection, draft.id);
    if (existing != null) {
      if (existing['organizerId'] != actor.uid) {
        throw const EventActionException('Cet identifiant est déjà utilisé. Rouvrez le formulaire.');
      }
      _putLocal(EventModel.fromMap(draft.id, existing)); // nouvel essai : déjà enregistré
      return;
    }
    final invalid = EventValidators.eventContent(draft) ??
        EventValidators.start(draft.startDate, now: now) ??
        _notNew(draft);
    if (invalid != null) throw EventActionException(invalid);

    final others = _storedEvents();
    final duplicate =
        EventValidators.duplicate(organizerId: actor.uid, title: draft.title, start: draft.startDate, existing: others);
    if (duplicate != null) throw EventActionException(duplicate);
    final limit = EventValidators.dailyLimit(organizerId: actor.uid, existing: others, now: now);
    if (limit != null) throw EventActionException(limit);

    final data = draft.copyWith(createdAt: now, updatedAt: now).toMap();
    await _write(draft.id, () => _store.set(_collection, draft.id, data));
  }

  /// Un événement créé part actif, sans inscrits, présents ni payés.
  static String? _notNew(EventModel draft) {
    if (draft.status != EventStatus.active || draft.cancelReason != null || draft.cancelledAt != null) {
      return 'Un nouvel événement ne peut pas être annulé.';
    }
    if (draft.registeredUserIds.isNotEmpty || draft.checkedInUserIds.isNotEmpty || draft.paidUserIds.isNotEmpty) {
      return 'Un nouvel événement commence sans inscrits.';
    }
    return null;
  }

  // ---------------------------------------------- Modification / annulation

  /// Modification (règle 5) : écrit SEULEMENT les champs changés (+ updatedAt)
  /// sur la version enregistrée, jamais le document entier, sinon les
  /// inscriptions faites entre-temps seraient effacées. organizerId n'est
  /// jamais modifié. Une affiche remplacée ou retirée est supprimée du
  /// téléphone.
  ///
  /// Vérifié ici : organisateur ou admin ; ni terminé ni annulé ; capacité
  /// jamais sous le nombre d'inscrits ; contenu final valide ; un début
  /// modifié doit être dans au moins 15 minutes. Seuls les champs
  /// modifiables sont écrits : jamais organizerId, createdAt, le statut, les
  /// inscrits, présents ou payés.
  Future<void> updateEvent(EventModel original, EventModel edited) async {
    final actor = _requireActor('modifier un événement');
    final now = DateTime.now();
    final current = _readStored(original.id); // inscrits les plus récents
    _requireManager(actor, current, 'modifier cet événement');

    final blocked = EventValidators.editBlocked(current, now);
    if (blocked != null) throw EventActionException(blocked);
    final capacityError = EventValidators.capacity(edited.capacity?.toString(),
        registeredCount: current.registeredUserIds.length);
    if (capacityError != null) throw EventActionException(capacityError);

    final changes = edited.changedFieldsSince(original);
    if (changes.isEmpty) return; // rien à enregistrer
    // Contenu final (version enregistrée + changements), comme l'ancien serveur.
    final merged = EventModel.fromMap(current.id, {...current.toMap(), ...changes});
    final invalid = EventValidators.eventContent(merged) ??
        (changes.containsKey('startDate') ? EventValidators.start(merged.startDate, now: now) : null);
    if (invalid != null) throw EventActionException(invalid);
    final patch = {...changes, 'updatedAt': now};

    await _write(original.id, () => _store.update(_collection, original.id, patch));
    if (changes.containsKey('posterUrl') && current.posterUrl != edited.posterUrl) {
      await _storage.delete(current.posterUrl);
    }
  }

  /// Annulation (règle 6) : organisateur ou admin ; ni déjà annulé ni
  /// terminé ; motif de 5 à 200 caractères ; les inscriptions sont conservées.
  Future<void> cancelEvent(EventModel event, String reason) async {
    final actor = _requireActor('annuler un événement');
    final now = DateTime.now();
    final current = _readStored(event.id);
    _requireManager(actor, current, 'annuler cet événement');
    final blocked = EventRules.cancelBlocked(current, now) ?? EventValidators.cancelReason(reason);
    if (blocked != null) throw EventActionException(blocked);

    final patch = {
      'status': EventStatus.cancelled.name,
      'cancelReason': EventValidators.normalize(reason),
      'cancelledAt': now,
      'updatedAt': now,
    };
    await _write(event.id, () => _store.update(_collection, event.id, patch));
  }

  // ------------------------------------------------------------ Suppression

  /// Suppression (règle 7) : organisateur ou admin seulement ; refusée à
  /// l'organisateur si des personnes sont inscrites
  /// ([EventHasRegistrantsException] → l'écran propose d'annuler) ; l'admin
  /// peut toujours supprimer. Le rôle vient de la session, pas de l'écran.
  /// L'affiche est supprimée du téléphone.
  Future<void> deleteEvent(EventModel event) async {
    final actor = _requireActor('supprimer un événement');
    final data = _store.get(_collection, event.id);
    final current = data == null ? (findById(event.id) ?? event) : EventModel.fromMap(event.id, data);
    _requireManager(actor, current, 'supprimer cet événement');
    final blocked = EventRules.deleteBlocked(current, isAdmin: actor.isAdmin);
    if (blocked != null) throw EventHasRegistrantsException(blocked);

    try {
      await _store.delete(_collection, event.id);
    } catch (e) {
      debugPrint('Suppression événement ${event.id} : $e');
      throw const EventActionException('Impossible de supprimer. Réessayez.');
    }
    await _storage.delete(current.posterUrl);
    _all = _all.where((e) => e.id != event.id).toList();
    notifyListeners();
  }

  // ----------------------------------------------- Participants (organisateur)

  /// Pointages en cours, par « événement|liste|uid » : bloque le double tap.
  final Set<String> _busyAttendance = {};
  bool isAttendanceBusy(String eventId, String field, String uid) => _busyAttendance.contains('$eventId|$field|$uid');

  /// Noms des inscrits, mis en cache (uid → nom complet).
  final Map<String, String> _names = {};

  /// Noms des [uids] lus dans les comptes enregistrés (users/{uid}). Un uid
  /// sans compte ou sans nom est absent du résultat : l'écran utilise un nom
  /// de repli.
  Future<Map<String, String>> attendeeNames(List<String> uids) async {
    for (final uid in uids.toSet()) {
      if (_names.containsKey(uid)) continue;
      try {
        final name = (_store.get(AppConstants.usersCollection, uid)?['fullName'] ?? '').toString().trim();
        if (name.isNotEmpty) _names[uid] = name;
      } catch (e) {
        debugPrint('Lecture du nom de $uid échouée : $e');
      }
    }
    return {for (final u in uids) if (_names.containsKey(u)) u: _names[u]!};
  }

  /// Bascule « présent » (checkedInUserIds) pour [uid].
  Future<void> togglePresent(String eventId, String uid) => _toggleAttendance(eventId, 'checkedInUserIds', uid);

  /// Bascule « payé » (paidUserIds) pour [uid].
  Future<void> togglePaid(String eventId, String uid) => _toggleAttendance(eventId, 'paidUserIds', uid);

  /// Scan d'un billet : POINTE présent, ne retire jamais (déjà présent : rien).
  Future<void> markPresent(String eventId, String uid) =>
      _toggleAttendance(eventId, 'checkedInUserIds', uid, onlyAdd: true);

  /// Ajoute ou retire UN uid d'UNE seule liste, sur la version enregistrée
  /// (lecture et écriture sans `await` entre les deux) : deux pointages
  /// successifs ne s'écrasent pas.
  Future<void> _toggleAttendance(String eventId, String field, String uid, {bool onlyAdd = false}) async {
    final key = '$eventId|$field|$uid';
    if (_busyAttendance.contains(key)) return; // double tap ignoré
    final actor = _requireActor('pointer les participants');
    final current = _readStored(eventId);
    // Organisateur ou admin seulement, comme l'ancien serveur (isAttendanceChange).
    _requireManager(actor, current, 'pointer les participants');
    final isPresentList = field == 'checkedInUserIds';
    final blocked = isPresentList
        ? EventRules.presentBlockedReason(current, uid, DateTime.now())
        : EventRules.paidBlockedReason(current, uid);
    if (blocked != null) throw EventActionException(blocked);

    final list = isPresentList ? current.checkedInUserIds : current.paidUserIds;
    final add = !list.contains(uid);
    if (onlyAdd && !add) return; // déjà dans la liste : on ne retire jamais
    final newList = add ? [...list, uid] : list.where((id) => id != uid).toList();
    _busyAttendance.add(key);
    notifyListeners();
    try {
      await _write(eventId, () => _store.update(_collection, eventId, {field: newList}));
    } finally {
      _busyAttendance.remove(key);
      notifyListeners();
    }
  }

  // ------------------------------------------------------------ Inscription

  /// Même chose que [toggleRegistrationWithResult], sans le résultat
  /// (bouton « Je participe » de l'accueil).
  Future<void> toggleRegistration(EventModel event, String? userId) =>
      toggleRegistrationWithResult(event, userId);

  /// Inscription / désinscription (règles 1, 2 et 4).
  ///
  /// On relit l'événement enregistré, on vérifie les règles (capacité,
  /// dates, annulation) puis on écrit, sans `await` entre les deux : si deux
  /// personnes visent la dernière place, la seconde voit l'événement complet.
  /// Une désinscription retire aussi l'uid des présents / payés.
  /// Renvoie true si l'utilisateur est maintenant inscrit, false s'il est
  /// désinscrit, null si le tap est ignoré (écriture déjà en cours).
  ///
  /// Chacun n'inscrit ou ne désinscrit que lui-même : [userId] doit être la
  /// personne de la session (organisateur et admin compris, comme l'ancien
  /// serveur).
  Future<bool?> toggleRegistrationWithResult(EventModel event, String? userId) async {
    if (_busyEventIds.contains(event.id)) return null; // double tap ignoré
    if (userId != null) {
      final actor = _actor;
      if (actor == null) throw const EventActionException('Connectez-vous pour vous inscrire.');
      if (actor.uid != userId) {
        throw const EventActionException('Vous ne pouvez inscrire ou désinscrire que vous-même.');
      }
    }

    final current = _readStored(event.id);
    final register = userId == null || !current.isUserRegistered(userId);
    final now = DateTime.now();
    final blocked = register
        ? EventRules.registrationBlocked(current, userId, now)
        : EventRules.unregistrationBlocked(current, userId, now);
    if (blocked != null) {
      _putLocal(current); // la liste montrait peut-être une version périmée
      throw EventActionException(blocked);
    }

    final uid = userId!;
    final updated = current.copyWithRegistration(uid, register);
    _busyEventIds.add(event.id);
    notifyListeners();
    try {
      await _write(
          event.id,
          () => _store.update(_collection, event.id, {
                'registeredUserIds': updated.registeredUserIds,
                // Désinscription : il n'est plus ni présent ni payé.
                if (!register) 'checkedInUserIds': updated.checkedInUserIds,
                if (!register) 'paidUserIds': updated.paidUserIds,
              }));
      return register;
    } finally {
      _busyEventIds.remove(event.id);
      notifyListeners();
    }
  }

  // La synchronisation calendrier n'est pas ici : voir event_calendar_sync.dart
  // (logique pure) et event_calendar_launcher.dart (appel au plugin).
}
