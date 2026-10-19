import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/local_cache_service.dart';
import '../core/utils/offline_queue_service.dart';
import '../models/event_model.dart';
import '../screens/evenements/event_validators.dart';
import '../services/firestore_repository.dart';

/// Erreur d'action sur un événement, avec un message prêt à afficher.
class EventActionException implements Exception {
  final String message;
  const EventActionException(this.message);

  @override
  String toString() => message;
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

/// Gestion des Événements — CRUD + synchronisation calendrier natif +
/// vue carte géolocalisée (fonctionnalités avancées).
class EventProvider extends ChangeNotifier {
  final _repo = FirestoreRepository<EventModel>(
    collectionName: AppConstants.eventsCollection,
    cacheBoxName: AppConstants.hiveEventsBox,
    fromMap: EventModel.fromMap,
    toMap: (e) => e.toMap(),
  );

  final _firestore = FirebaseFirestore.instance;
  final _cache = LocalCacheService();
  final _queue = OfflineQueueService();

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
  String? categoryFilter;

  List<EventModel> get upcoming {
    final now = DateTime.now();
    var list = _all.where((e) => e.startDate.isAfter(now)).toList();
    if (categoryFilter != null) {
      list = list.where((e) => e.category == categoryFilter).toList();
    }
    list.sort((a, b) => a.startDate.compareTo(b.startDate));
    return list;
  }

  List<EventModel> eventsOnDay(DateTime day) {
    return _all.where((e) =>
        e.startDate.year == day.year &&
        e.startDate.month == day.month &&
        e.startDate.day == day.day).toList();
  }

  List<EventModel> get publicPreview => upcoming.take(5).toList();

  /// Version la plus récente d'un événement (null s'il n'est plus chargé).
  EventModel? findById(String id) {
    for (final e in _all) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<void> load() async {
    isLoading = true;
    notifyListeners();
    _all = await _repo.fetchAll(isOnline: _isOnline);
    isLoading = false;
    notifyListeners();
  }

  void setCategoryFilter(String? category) {
    categoryFilter = category;
    notifyListeners();
  }

  /// Création. [draft.id] est généré UNE fois à l'ouverture du formulaire et
  /// réutilisé à chaque nouvel essai : réécrire le même document ne crée
  /// jamais de doublon, même si le premier essai a réussi sans réponse.
  /// Hors-ligne, le dépôt met la création en file d'attente.
  Future<String> createEvent(EventModel draft) async {
    // Horloge du téléphone (pas de serverTimestamp : la file Hive ne peut
    // pas stocker un FieldValue).
    final now = DateTime.now();
    final id = await _repo.create(
      draft.copyWith(createdAt: now, updatedAt: now),
      isOnline: _isOnline,
      explicitId: draft.id.isEmpty ? null : draft.id,
    );
    await load();
    return id;
  }

  /// Modification : envoie SEULEMENT les champs changés (+ updatedAt) avec
  /// update(), jamais un set() du document entier, sinon les inscriptions
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

    var sentOnline = _isOnline;
    if (_isOnline) {
      try {
        await _firestore
            .collection(AppConstants.eventsCollection)
            .doc(original.id)
            .update(patch)
            .timeout(const Duration(seconds: 15));
      } on FirebaseException catch (e) {
        debugPrint('Modification événement ${original.id} : ${e.code}');
        // Seule une panne réseau justifie la file d'attente. Un refus
        // (permission-denied...) serait refusé à nouveau à chaque essai.
        if (e.code != 'unavailable') throw EventActionException(friendlyFirebaseMessage(e));
        sentOnline = false;
      } on TimeoutException {
        throw const EventActionException('Le serveur ne répond pas. Vérifiez votre connexion et réessayez.');
      }
    }
    if (!sentOnline) {
      // Le patch partiel est rejoué plus tard avec merge : il ne touche que ces champs.
      _queue.enqueue(
        type: QueueActionType.update,
        collection: AppConstants.eventsCollection,
        payload: patch,
        docId: original.id,
      );
    }

    // Mise à jour locale : on applique le patch sur la version la plus récente
    // (les inscriptions restent celles du serveur, pas celles du formulaire).
    final updated = EventModel.fromMap(original.id, {...current.toMap(), ...patch})
        .copyWith(pendingSync: !sentOnline);
    _all = [for (final e in _all) e.id == updated.id ? updated : e];
    final cached = _cache.readCollection(AppConstants.hiveEventsBox)[original.id] ?? current.toMap();
    await _cache.upsert(AppConstants.hiveEventsBox, original.id, {...cached, ...patch});
    notifyListeners();
    return sentOnline;
  }

  /// Inscription / désinscription atomique, en ligne uniquement.
  ///
  /// arrayUnion / arrayRemove demandent au serveur d'ajouter ou retirer
  /// UN uid : deux inscriptions simultanées ne s'écrasent plus. On n'utilise
  /// pas la file d'attente : elle est stockée dans Hive, qui ne sait pas
  /// enregistrer un FieldValue, et une liste complète rejouée plus tard
  /// effacerait les inscriptions faites entre-temps.
  /// Renvoie true si l'utilisateur est maintenant inscrit, false s'il est
  /// désinscrit, null si le tap est ignoré (requête déjà en cours).
  Future<bool?> toggleRegistration(EventModel event, String userId) async {
    if (_busyEventIds.contains(event.id)) return null; // double tap ignoré
    if (!_isOnline) {
      throw const EventActionException('Connexion requise pour vous inscrire ou vous désinscrire.');
    }

    final current = findById(event.id) ?? event;
    final register = !current.isUserRegistered(userId);
    _busyEventIds.add(event.id);
    notifyListeners();
    try {
      await _firestore.collection(AppConstants.eventsCollection).doc(event.id).update({
        'registeredUserIds':
            register ? FieldValue.arrayUnion([userId]) : FieldValue.arrayRemove([userId]),
      }).timeout(const Duration(seconds: 15));

      // Succès : on met à jour la liste locale et le cache avec des valeurs
      // simples (List<String>), jamais avec le FieldValue.
      final updated = current.copyWithRegistration(userId, register);
      _all = [for (final e in _all) e.id == updated.id ? updated : e];
      final cached = _cache.readCollection(AppConstants.hiveEventsBox)[event.id] ?? {};
      await _cache.upsert(AppConstants.hiveEventsBox, event.id,
          {...cached, 'registeredUserIds': updated.registeredUserIds});
      return register;
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

  Future<void> deleteEvent(String id) async {
    await _repo.delete(id, isOnline: _isOnline);
    await load();
  }

  /// Synchronisation avec le calendrier natif du téléphone — fonctionnalité
  /// avancée : ajoute l'événement + un rappel 30 min avant.
  ///
  /// Génère un lien Google Calendar (ouvert dans le navigateur/l'app
  /// Calendrier) plutôt que d'utiliser un plugin natif, pour rester
  /// compatible avec toutes les plateformes sans dépendance Kotlin.
  String buildCalendarLink(EventModel event) {
    final start = event.startDate.toUtc();
    final end = event.startDate.add(const Duration(hours: 2)).toUtc();
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}'
        'T${d.hour.toString().padLeft(2, '0')}${d.minute.toString().padLeft(2, '0')}${d.second.toString().padLeft(2, '0')}Z';
    final params = {
      'action': 'TEMPLATE',
      'text': event.title,
      'dates': '${fmt(start)}/${fmt(end)}',
      'details': event.description,
      'location': event.location,
    };
    final query = params.entries
        .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return 'https://calendar.google.com/calendar/render?$query';
  }
}
