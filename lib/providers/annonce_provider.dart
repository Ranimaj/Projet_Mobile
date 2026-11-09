import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import '../models/annonce_model.dart';
import '../services/local_repository.dart';
import '../services/local_store.dart';

/// Gestion des Annonces (campus) — CRUD + épinglage automatique des
/// annonces officielles. Données stockées sur le téléphone (SQLite).
class AnnonceProvider extends ChangeNotifier {
  AnnonceProvider({LocalStore? store})
      : _repo = LocalRepository<AnnonceModel>(
          collectionName: AppConstants.annoncesCollection,
          fromMap: AnnonceModel.fromMap,
          toMap: (a) => a.toMap(),
          store: store,
        );

  final LocalRepository<AnnonceModel> _repo;

  /// Sans effet : tout est local, le réseau ne change rien. Conservé pour
  /// le ChangeNotifierProxyProvider de main.dart.
  void updateConnectivity(bool online) {}

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
    _all = _repo.fetchAll();
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

    final id = await _repo.create(toSave);
    await load();
    return id;
  }

  Future<void> pinAnnonce(String id, bool pinned) async {
    await _repo.update(id, {'isPinned': pinned});
    await load();
  }

  Future<void> deleteAnnonce(String id) async {
    await _repo.delete(id);
    await load();
  }
}
