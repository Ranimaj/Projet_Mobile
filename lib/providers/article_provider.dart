import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import '../models/article_model.dart';
import '../services/firestore_repository.dart';
import '../services/storage_service.dart';

/// Gestion Vente & Don — CRUD complet + recherche/filtres avancés +
/// upload multi-images compressées. Fonctionne hors-ligne (BNF3).
class ArticleProvider extends ChangeNotifier {
  final _repo = FirestoreRepository<ArticleModel>(
    collectionName: AppConstants.articlesCollection,
    cacheBoxName: AppConstants.hiveArticlesBox,
    fromMap: ArticleModel.fromMap,
    toMap: (a) => a.toMap(),
  );
  final _storage = StorageService();

  bool _isOnline = true;
  void updateConnectivity(bool online) => _isOnline = online;

  List<ArticleModel> _all = [];
  bool isLoading = false;

  String searchQuery = '';
  String? categoryFilter;
  bool showOnlyFree = false;

  List<ArticleModel> get items {
    var list = _all.where((a) => a.status != ArticleStatus.done);
    if (searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      list = list.where((a) =>
          a.title.toLowerCase().contains(q) || a.description.toLowerCase().contains(q));
    }
    if (categoryFilter != null) {
      list = list.where((a) => a.category == categoryFilter);
    }
    if (showOnlyFree) {
      list = list.where((a) => a.isFree);
    }
    return list.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<ArticleModel> favoritesOf(String userId) =>
      _all.where((a) => a.favoritedBy.contains(userId)).toList();

  Future<void> load() async {
    isLoading = true;
    notifyListeners();
    _all = await _repo.fetchAll(isOnline: _isOnline);
    isLoading = false;
    notifyListeners();
  }

  void setSearch(String query) {
    searchQuery = query;
    notifyListeners();
  }

  void setCategoryFilter(String? category) {
    categoryFilter = category;
    notifyListeners();
  }

  void toggleFreeOnly() {
    showOnlyFree = !showOnlyFree;
    notifyListeners();
  }

  Future<String> createArticle({
    required ArticleModel draft,
    required List<dynamic> imageFiles, // List<File>
  }) async {
    List<String> urls = [];
    if (_isOnline && imageFiles.isNotEmpty) {
      urls = await _storage.uploadImages(List.from(imageFiles), folder: 'articles');
    }
    final toSave = draft.copyWith(imageUrls: urls);
    final id = await _repo.create(toSave, isOnline: _isOnline);
    await load();
    return id;
  }

  Future<void> updateArticle(String id, Map<String, dynamic> patch) async {
    await _repo.update(id, patch, isOnline: _isOnline);
    await load();
  }

  Future<void> markAsReserved(String id) =>
      updateArticle(id, {'status': ArticleStatus.reserved.name});

  Future<void> markAsDone(String id) =>
      updateArticle(id, {'status': ArticleStatus.done.name});

  Future<void> deleteArticle(String id) async {
    await _repo.delete(id, isOnline: _isOnline);
    await load();
  }

  Future<void> toggleFavorite(String articleId, String userId) async {
    final article = _all.firstWhere((a) => a.id == articleId);
    final favs = List<String>.from(article.favoritedBy);
    favs.contains(userId) ? favs.remove(userId) : favs.add(userId);
    await updateArticle(articleId, {'favoritedBy': favs});
  }
}
