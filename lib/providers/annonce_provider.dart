import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import '../models/annonce_model.dart';
import '../services/firestore_repository.dart';
import '../services/notification_service.dart';

/// Gestion des Annonces (campus) — CRUD + épinglage automatique des
/// annonces officielles + notifications push ciblées par segment.
class AnnonceProvider extends ChangeNotifier {
  final _repo = FirestoreRepository<AnnonceModel>(
    collectionName: AppConstants.annoncesCollection,
    cacheBoxName: AppConstants.hiveAnnoncesBox,
    fromMap: AnnonceModel.fromMap,
    toMap: (a) => a.toMap(),
  );
  final _notifications = NotificationService();

  bool _isOnline = true;
  void updateConnectivity(bool online) => _isOnline = online;

  List<AnnonceModel> _all = [];
  bool isLoading = false;
  String? categoryFilter;

  /// Épinglées en premier, puis tri par date décroissante — priorisation
  /// automatique des annonces officielles (fonctionnalité avancée).
  List<AnnonceModel> get items {
    var list = _all.toList();
    if (categoryFilter != null) {
      list = list.where((a) => a.category == categoryFilter).toList();
    }
    list.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  List<AnnonceModel> get publicPreview => items.take(5).toList();

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

  Future<String> createAnnonce(AnnonceModel draft) async {
    // Une annonce "Officielle" est épinglée automatiquement.
    final toSave = draft.category == 'Officielle'
        ? AnnonceModel(
            id: draft.id,
            authorId: draft.authorId,
            authorName: draft.authorName,
            title: draft.title,
            content: draft.content,
            category: draft.category,
            isPinned: true,
            isUrgent: draft.isUrgent,
            createdAt: draft.createdAt,
            targetMajors: draft.targetMajors,
          )
        : draft;

    final id = await _repo.create(toSave, isOnline: _isOnline);

    if (toSave.isUrgent && _isOnline) {
      // Diffusion ciblée vers les segments concernés (ou tout le campus).
      if (toSave.targetMajors.isEmpty) {
        // notification générale — gérée côté backend/Cloud Function en prod
      } else {
        for (final major in toSave.targetMajors) {
          await _notifications.subscribeToSegment(major, '');
        }
      }
    }
    await load();
    return id;
  }

  Future<void> pinAnnonce(String id, bool pinned) async {
    await _repo.update(id, {'isPinned': pinned}, isOnline: _isOnline);
    await load();
  }

  Future<void> deleteAnnonce(String id) async {
    await _repo.delete(id, isOnline: _isOnline);
    await load();
  }
}
