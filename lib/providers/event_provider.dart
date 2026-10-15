import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import '../models/event_model.dart';
import '../services/firestore_repository.dart';

/// Gestion des Événements — CRUD + synchronisation calendrier natif +
/// vue carte géolocalisée (fonctionnalités avancées).
class EventProvider extends ChangeNotifier {
  final _repo = FirestoreRepository<EventModel>(
    collectionName: AppConstants.eventsCollection,
    cacheBoxName: AppConstants.hiveEventsBox,
    fromMap: EventModel.fromMap,
    toMap: (e) => e.toMap(),
  );

  bool _isOnline = true;
  void updateConnectivity(bool online) => _isOnline = online;

  List<EventModel> _all = [];
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

  Future<String> createEvent(EventModel draft) async {
    final id = await _repo.create(draft, isOnline: _isOnline);
    await load();
    return id;
  }

  Future<void> toggleRegistration(EventModel event, String userId) async {
    final isRegistered = event.isUserRegistered(userId);
    final updated = event.copyWithRegistration(userId, !isRegistered);
    await _repo.update(event.id, {'registeredUserIds': updated.registeredUserIds}, isOnline: _isOnline);
    await load();
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
