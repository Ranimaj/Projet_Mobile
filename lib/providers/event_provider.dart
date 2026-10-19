import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/local_cache_service.dart';
import '../core/utils/offline_queue_service.dart';
import '../models/event_model.dart';
import '../screens/evenements/event_rules.dart';
import '../screens/evenements/event_validators.dart';

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

/// Traduit les codes d'erreur Firebase en messages compréhensibles.
String friendlyFirebaseMessage(FirebaseException e) {
  switch (e.code) {
    case 'permission-denied':
      return 'Action refusée. La liste a peut-être changé : réessayez.';
    case 'unavailable':
      return 'Serveur injoignable. Vérifiez votre connexion et réessayez.';
    case 'not-found':
      return "Cet événement n'existe plus.";
    case 'failed-precondition':
      return 'Action impossible pour le moment. Réessayez.';
    default:
      return 'Une erreur est survenue. Réessayez.';
  }
}

/// Gestion des Événements : lecture (cache hors-ligne), création,
/// modification, annulation, suppression, inscription et filtres.
///
/// Les écritures passent directement par Firestore quand on est en ligne.
/// La file d'attente hors-ligne n'est utilisée que pour une panne réseau
/// (« unavailable » ou pas de connexion), jamais pour un refus du serveur.
class EventProvider extends ChangeNotifier {
  final _firestore = FirebaseFirestore.instance;
  final _cache = LocalCacheService();
  final _queue = OfflineQueueService();
  static const _timeout = Duration(seconds: 15);

  bool _isOnline = true;
  bool get isOnline => _isOnline;
  void updateConnectivity(bool online) => _isOnline = online;

  /// Événements dont une inscription/désinscription est en cours d'envoi.
  final Set<String> _busyEventIds = {};
  bool isRegistrationBusy(String eventId) => _busyEventIds.contains(eventId);

  List<EventModel> _all = [];
  /// Tous les événements chargés (lecture seule), pour les contrôles du formulaire.
  List<EventModel> get all => List.unmodifiable(_all);
  bool isLoading = false;

  DocumentReference<Map<String, dynamic>> _doc(String id) =>
      _firestore.collection(AppConstants.eventsCollection).doc(id);

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

  /// Liste affichée : filtre principal + catégorie + jour + recherche + prix,
  /// triée par début.
  List<EventModel> visibleEvents(String? userId, {String query = ''}) => EventRules.filter(_all,
      filter: filter,
      now: DateTime.now(),
      userId: userId,
      category: categoryFilter,
      day: selectedDay,
      query: query,
      price: priceFilter);

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

  /// Message d'erreur du dernier chargement (null = OK). En cas d'échec, la
  /// liste affichée est celle du cache Hive.
  String? loadError;

  List<EventModel> _readCache() => _cache
      .readCollection(AppConstants.hiveEventsBox)
      .entries
      .map((e) => EventModel.fromMap(e.key, e.value))
      .toList();

  /// Lecture : Firestore si en ligne (puis mise en cache), sinon le cache.
  /// On lit Firestore ici plutôt que via le dépôt partagé pour pouvoir
  /// afficher une erreur avec « Réessayer » au lieu de l'avaler en silence.
  Future<void> load() async {
    isLoading = true;
    loadError = null;
    notifyListeners();
    if (_isOnline) {
      try {
        final snapshot = await _firestore.collection(AppConstants.eventsCollection).get().timeout(_timeout);
        final byId = {for (final doc in snapshot.docs) doc.id: doc.data()};
        await _cache.cacheCollection(AppConstants.hiveEventsBox, byId);
        _all = byId.entries.map((e) => EventModel.fromMap(e.key, e.value)).toList();
      } catch (e) {
        debugPrint('Chargement des événements échoué : $e');
        loadError = e is FirebaseException
            ? friendlyFirebaseMessage(e)
            : "Impossible d'actualiser les événements. Vérifiez votre connexion.";
        _all = _readCache();
      }
    } else {
      _all = _readCache();
    }
    isLoading = false;
    notifyListeners();
  }

  /// Écoute en temps réel UN événement (règle 10) : events/{id}.snapshots().
  /// Chaque nouvelle version met aussi à jour la copie du provider et le
  /// cache, pour que les actions (inscription…) partent des données les plus
  /// récentes. event == null : le document a été supprimé. fromCache : la
  /// donnée vient du cache local de Firestore (pas de réseau).
  Stream<({EventModel? event, bool fromCache})> watchEvent(String id) {
    return _doc(id).snapshots(includeMetadataChanges: true).asyncMap((snap) async {
      if (!snap.exists) {
        // Supprimé (ou jamais synchronisé) : on le retire de la liste locale.
        if (!snap.metadata.isFromCache && findById(id) != null) {
          _all = _all.where((e) => e.id != id).toList();
          await _cache.removeFromCache(AppConstants.hiveEventsBox, id);
          notifyListeners();
        }
        return (event: null, fromCache: snap.metadata.isFromCache);
      }
      final event = EventModel.fromMap(snap.id, snap.data()!);
      if (findById(id) != null) await _replaceLocal(event);
      return (event: event, fromCache: snap.metadata.isFromCache);
    });
  }

  /// Remplace un événement dans la liste locale et dans le cache Hive
  /// (valeurs simples uniquement, jamais de FieldValue).
  Future<void> _replaceLocal(EventModel updated) async {
    _all = [for (final e in _all) e.id == updated.id ? updated : e];
    await _cache.upsert(AppConstants.hiveEventsBox, updated.id, updated.toMap());
    notifyListeners();
  }

  // --------------------------------------------------------------- Création

  /// Date de création gardée par id : un nouvel essai réécrit exactement le
  /// même createdAt (les règles interdisent de le changer ensuite).
  final Map<String, DateTime> _createdAtById = {};

  /// Création. [draft.id] est généré UNE fois à l'ouverture du formulaire et
  /// réutilisé à chaque nouvel essai : réécrire le même document ne crée
  /// jamais de doublon, même si le premier essai a réussi sans réponse.
  /// Renvoie true si envoyé au serveur, false si mis en file d'attente.
  Future<bool> createEvent(EventModel draft) async {
    // Horloge du téléphone (pas de serverTimestamp : la file Hive ne peut
    // pas stocker un FieldValue).
    final createdAt = _createdAtById.putIfAbsent(draft.id, DateTime.now);
    final data = draft.copyWith(createdAt: createdAt, updatedAt: createdAt).toMap();

    var sentOnline = _isOnline;
    if (_isOnline) {
      try {
        await _doc(draft.id).set(data).timeout(_timeout);
      } on FirebaseException catch (e) {
        debugPrint('Création événement ${draft.id} : ${e.code}');
        if (e.code != 'unavailable') throw EventActionException(friendlyFirebaseMessage(e));
        sentOnline = false;
      }
      // TimeoutException remonte telle quelle : l'écran propose de réessayer
      // avec le même id.
    }
    if (!sentOnline) {
      _queue.enqueue(
        type: QueueActionType.create,
        collection: AppConstants.eventsCollection,
        payload: data,
        docId: draft.id,
      );
    }
    _createdAtById.remove(draft.id);
    await _cache.upsert(AppConstants.hiveEventsBox, draft.id, data);
    await load();
    return sentOnline;
  }

  // ---------------------------------------------- Modification / annulation

  /// Envoie un patch partiel : update() en ligne, file d'attente seulement si
  /// le réseau est absent ou « unavailable ». Renvoie true si envoyé.
  Future<bool> _sendPatch(String id, Map<String, dynamic> patch) async {
    if (_isOnline) {
      try {
        await _doc(id).update(patch).timeout(_timeout);
        return true;
      } on FirebaseException catch (e) {
        debugPrint('Mise à jour événement $id : ${e.code}');
        // Un refus (permission-denied...) serait refusé à nouveau à chaque essai.
        if (e.code != 'unavailable') throw EventActionException(friendlyFirebaseMessage(e));
      } on TimeoutException {
        throw const EventActionException('Le serveur ne répond pas. Vérifiez votre connexion et réessayez.');
      }
    }
    // Le patch partiel est rejoué plus tard avec merge : il ne touche que ces champs.
    _queue.enqueue(
      type: QueueActionType.update,
      collection: AppConstants.eventsCollection,
      payload: patch,
      docId: id,
    );
    return false;
  }

  /// Applique un patch sur la version locale la plus récente.
  Future<void> _applyPatchLocally(EventModel current, Map<String, dynamic> patch, bool sentOnline) =>
      _replaceLocal(EventModel.fromMap(current.id, {...current.toMap(), ...patch})
          .copyWith(pendingSync: !sentOnline));

  /// Modification (règle 5) : envoie SEULEMENT les champs changés (+ updatedAt)
  /// avec update(), jamais un set() du document entier, sinon les inscriptions
  /// faites entre-temps seraient effacées. organizerId n'est jamais envoyé.
  /// Renvoie true si envoyé au serveur, false si mis en file d'attente.
  Future<bool> updateEvent(EventModel original, EventModel edited) async {
    final now = DateTime.now();
    final current = findById(original.id) ?? original; // inscrits les plus récents

    final blocked = EventValidators.editBlocked(current, now);
    if (blocked != null) throw EventActionException(blocked);
    final capacityError = EventValidators.capacity(edited.capacity?.toString(),
        registeredCount: current.registeredUserIds.length);
    if (capacityError != null) throw EventActionException(capacityError);

    final changes = edited.changedFieldsSince(original);
    if (changes.isEmpty) return true; // rien à enregistrer
    final patch = {...changes, 'updatedAt': Timestamp.fromDate(now)};

    final sentOnline = await _sendPatch(original.id, patch);
    await _applyPatchLocally(current, patch, sentOnline);
    return sentOnline;
  }

  /// Annulation (règle 6) : motif de 5 à 200 caractères ; les inscriptions
  /// sont conservées. Renvoie true si envoyé au serveur.
  Future<bool> cancelEvent(EventModel event, String reason) async {
    final now = DateTime.now();
    final current = findById(event.id) ?? event;
    final blocked = EventRules.cancelBlocked(current, now) ?? EventValidators.cancelReason(reason);
    if (blocked != null) throw EventActionException(blocked);

    final patch = {
      'status': EventStatus.cancelled.name,
      'cancelReason': EventValidators.normalize(reason),
      'cancelledAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    };
    final sentOnline = await _sendPatch(event.id, patch);
    await _applyPatchLocally(current, patch, sentOnline);
    return sentOnline;
  }

  // ------------------------------------------------------------ Suppression

  /// Suppression (règle 7) : refusée à l'organisateur si des personnes sont
  /// inscrites ([EventHasRegistrantsException] → l'écran propose d'annuler) ;
  /// l'admin peut toujours supprimer. Connexion requise : une suppression
  /// mise en file pourrait être refusée plus tard sans que personne ne le voie.
  Future<void> deleteEvent(EventModel event, {required bool isAdmin}) async {
    final current = findById(event.id) ?? event;
    final blocked = EventRules.deleteBlocked(current, isAdmin: isAdmin);
    if (blocked != null) throw EventHasRegistrantsException(blocked);
    if (!_isOnline) throw const EventActionException('Connexion requise pour supprimer un événement.');

    try {
      await _doc(event.id).delete().timeout(_timeout);
    } on FirebaseException catch (e) {
      debugPrint('Suppression événement ${event.id} : ${e.code}');
      throw EventActionException(friendlyFirebaseMessage(e));
    } on TimeoutException {
      throw const EventActionException('Le serveur ne répond pas. Vérifiez votre connexion et réessayez.');
    }
    _all = _all.where((e) => e.id != event.id).toList();
    await _cache.removeFromCache(AppConstants.hiveEventsBox, event.id);
    notifyListeners();
  }

  // ----------------------------------------------- Participants (organisateur)

  /// Pointages en cours, par « événement|liste|uid » : bloque le double tap.
  final Set<String> _busyAttendance = {};
  bool isAttendanceBusy(String eventId, String field, String uid) => _busyAttendance.contains('$eventId|$field|$uid');

  /// Noms des inscrits, mis en cache (uid → nom complet).
  final Map<String, String> _names = {};

  /// Noms des [uids] depuis users/{uid} (lisibles par tous d'après les
  /// règles). Par paquets de 30 (limite d'une requête « in » Firestore).
  /// En cas d'échec : on renvoie ce qu'on a ; l'écran utilise un nom de repli.
  Future<Map<String, String>> attendeeNames(List<String> uids) async {
    final missing = uids.toSet().where((u) => !_names.containsKey(u)).toList();
    for (var i = 0; i < missing.length; i += 30) {
      final chunk = missing.sublist(i, i + 30 > missing.length ? missing.length : i + 30);
      try {
        final snap = await _firestore
            .collection(AppConstants.usersCollection)
            .where(FieldPath.documentId, whereIn: chunk)
            .get()
            .timeout(_timeout);
        for (final doc in snap.docs) {
          final name = (doc.data()['fullName'] ?? '').toString().trim();
          if (name.isNotEmpty) _names[doc.id] = name;
        }
      } catch (e) {
        debugPrint('Lecture des noms des inscrits échouée : $e');
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

  /// arrayUnion / arrayRemove sur UNE seule liste et UN seul uid : on ne
  /// réécrit jamais la liste entière (deux organisateurs qui pointent en même
  /// temps ne s'écrasent pas). Connexion requise, jamais de file d'attente.
  Future<void> _toggleAttendance(String eventId, String field, String uid, {bool onlyAdd = false}) async {
    final key = '$eventId|$field|$uid';
    if (_busyAttendance.contains(key)) return; // double tap ignoré
    final current = findById(eventId);
    if (current == null) throw const EventActionException("Cet événement n'existe plus.");
    final isPresentList = field == 'checkedInUserIds';
    final blocked = isPresentList
        ? EventRules.presentBlockedReason(current, uid, DateTime.now())
        : EventRules.paidBlockedReason(current, uid);
    if (blocked != null) throw EventActionException(blocked);
    if (!_isOnline) throw const EventActionException('Connexion requise pour modifier la liste.');

    final list = isPresentList ? current.checkedInUserIds : current.paidUserIds;
    final add = !list.contains(uid);
    if (onlyAdd && !add) return; // déjà dans la liste : on ne retire jamais
    _busyAttendance.add(key);
    notifyListeners();
    try {
      await _doc(eventId)
          .update({field: add ? FieldValue.arrayUnion([uid]) : FieldValue.arrayRemove([uid])})
          .timeout(_timeout);
      final newList = add ? [...list, uid] : list.where((id) => id != uid).toList();
      await _replaceLocal(
          isPresentList ? current.copyWith(checkedInUserIds: newList) : current.copyWith(paidUserIds: newList));
    } on FirebaseException catch (e) {
      debugPrint('Pointage $field $uid : ${e.code}');
      throw EventActionException(friendlyFirebaseMessage(e));
    } on TimeoutException {
      throw const EventActionException('Le serveur ne répond pas. Vérifiez votre connexion.');
    } finally {
      _busyAttendance.remove(key);
      notifyListeners();
    }
  }

  // ------------------------------------------------------------ Inscription

  /// Inscription / désinscription (règles 1, 2 et 4), en ligne uniquement.
  ///
  /// - Sans capacité : arrayUnion / arrayRemove, le serveur ajoute ou retire
  ///   UN uid, deux inscriptions simultanées ne s'écrasent plus.
  /// - Avec capacité : transaction (lire, vérifier, écrire). Si deux
  ///   personnes visent la dernière place, Firestore rejoue la transaction de
  ///   la seconde, qui voit alors l'événement complet.
  /// Pas de file d'attente : Hive ne sait pas stocker un FieldValue, et une
  /// place limitée ne peut pas être promise sans le serveur.
  /// Renvoie true si l'utilisateur est maintenant inscrit, false s'il est
  /// désinscrit, null si le tap est ignoré (requête déjà en cours).
  Future<bool?> toggleRegistration(EventModel event, String? userId) async {
    if (_busyEventIds.contains(event.id)) return null; // double tap ignoré

    final current = findById(event.id) ?? event;
    final register = userId == null || !current.isUserRegistered(userId);
    final now = DateTime.now();
    final blocked = register
        ? EventRules.registrationBlocked(current, userId, now)
        : EventRules.unregistrationBlocked(current, userId, now);
    if (blocked != null) throw EventActionException(blocked);
    if (!_isOnline) {
      throw EventActionException(current.capacity != null
          ? 'Connexion requise : places limitées.'
          : 'Connexion requise pour vous inscrire ou vous désinscrire.');
    }

    final uid = userId!;
    _busyEventIds.add(event.id);
    notifyListeners();
    try {
      EventModel updated;
      if (register && current.capacity != null) {
        final fresh = await _firestore.runTransaction<EventModel>((tx) async {
          final snap = await tx.get(_doc(event.id));
          if (!snap.exists) throw const EventActionException("Cet événement n'existe plus.");
          final latest = EventModel.fromMap(snap.id, snap.data()!);
          final reason = EventRules.registrationBlocked(latest, uid, DateTime.now());
          if (reason != null) throw EventActionException(reason);
          tx.update(_doc(event.id), {
            'registeredUserIds': FieldValue.arrayUnion([uid]),
          });
          return latest;
        }).timeout(_timeout);
        updated = fresh.copyWithRegistration(uid, true);
      } else {
        await _doc(event.id).update({
          'registeredUserIds': register ? FieldValue.arrayUnion([uid]) : FieldValue.arrayRemove([uid]),
          // Désinscription : on le retire aussi des présents / payés, dans la
          // MÊME écriture (les règles l'autorisent seulement dans ce cas).
          if (!register && current.checkedInUserIds.contains(uid))
            'checkedInUserIds': FieldValue.arrayRemove([uid]),
          if (!register && current.paidUserIds.contains(uid)) 'paidUserIds': FieldValue.arrayRemove([uid]),
        }).timeout(_timeout);
        updated = current.copyWithRegistration(uid, register);
      }
      await _replaceLocal(updated);
      return register;
    } on EventActionException {
      await load(); // la transaction a vu un état plus récent : on se resynchronise
      rethrow;
    } on FirebaseException catch (e) {
      debugPrint('Inscription événement ${event.id} refusée : ${e.code}');
      await load(); // on resynchronise avec le serveur avant de réessayer
      throw EventActionException(friendlyFirebaseMessage(e));
    } on TimeoutException {
      throw const EventActionException('Le serveur ne répond pas. Vérifiez votre connexion.');
    } finally {
      _busyEventIds.remove(event.id);
      notifyListeners();
    }
  }

  // La synchronisation calendrier n'est pas ici : voir event_calendar_sync.dart
  // (logique pure) et event_calendar_launcher.dart (appel au plugin).
}
