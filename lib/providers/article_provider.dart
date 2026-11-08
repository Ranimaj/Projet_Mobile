import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/utils/article_search.dart';
import '../core/utils/geo.dart';
import '../models/article_model.dart';
import '../services/ai/price_advisor.dart';
import '../services/ai/recommender.dart';
import '../services/local_photo_store.dart';
import '../services/location_service.dart';
import '../services/sqlite/article_store.dart';
import '../services/sqlite/local_article_repository.dart';

/// Gestion Vente & Don — CRUD complet, recherche intelligente avec filtres
/// combinés (texte, catégorie, gratuit, prix, distance, tri), photos
/// compressées, favoris et compteur de vues.
///
/// **Tout est dans la base SQLite du téléphone** ([LocalArticleRepository]) :
/// pas de Firebase, donc la gestion marche avec ou sans réseau. Les photos
/// sont copiées dans le dossier de l'app ([LocalPhotoStore]).
class ArticleProvider extends ChangeNotifier {
  ArticleProvider({
    ArticleStore? repository,
    LocationLookup? locate,
    DateTime Function()? clock,
    LocalPhotoStore? photos,
  })  : _repoOverride = repository,
        _locate = locate ?? currentLocation,
        _clock = clock ?? DateTime.now,
        _photosOverride = photos;

  final ArticleStore? _repoOverride;
  final LocationLookup _locate;
  final DateTime Function() _clock;
  final LocalPhotoStore? _photosOverride;
  static const _uuid = Uuid();

  // Créés à la première utilisation : les tests injectent des doublures.
  late final ArticleStore _repo = _repoOverride ?? LocalArticleRepository();
  late final LocalPhotoStore _photos = _photosOverride ?? LocalPhotoStore();

  bool _isOnline = true;

  /// État du réseau (affichage seulement : la gestion n'en dépend pas).
  bool get isOnline => _isOnline;

  /// Appelé par main.dart à chaque changement de réseau.
  void updateConnectivity(bool online) => _isOnline = online;

  List<ArticleModel> _all = [];
  bool isLoading = false;

  /// Tous les articles chargés, y compris vendus / donnés.
  List<ArticleModel> get all => List.unmodifiable(_all);

  // --- Recherche & filtres ---------------------------------------------------

  ArticleFilters _filters = ArticleFilters.none;
  ArticleFilters get filters => _filters;

  String get searchQuery => _filters.query;
  String? get categoryFilter => _filters.category;
  bool get showOnlyFree => _filters.freeOnly;

  /// Articles visibles dans la liste : non terminés, filtrés et triés — ou,
  /// pendant une recherche par photo, classés par ressemblance avec la photo.
  List<ArticleModel> get items {
    final filtered = filterArticles(
      _all.where((a) => a.status != ArticleStatus.done),
      _filters,
      from: _position,
    );
    final labels = _photoLabels;
    return labels == null ? filtered : rankByPhoto(filtered, labels);
  }

  // --- IA : recherche par photo, recommandations, prix conseillé ------------

  List<String>? _photoLabels;

  /// Une recherche par photo est en cours.
  bool get isPhotoSearch => _photoLabels != null;

  /// Classe la liste par ressemblance avec une photo ([labels] = étiquettes
  /// reconnues sur cette photo).
  void setPhotoSearch(List<String> labels) {
    _photoLabels = [for (final l in labels) l.toLowerCase()];
    notifyListeners();
  }

  void clearPhotoSearch() {
    if (_photoLabels == null) return;
    _photoLabels = null;
    notifyListeners();
  }

  /// « Pour toi » : articles proches des favoris et des articles consultés.
  List<ArticleModel> recommendationsFor(String userId, {int limit = 6}) =>
      recommendArticles(_all, userId, viewedIds: _viewed, limit: limit, now: _clock());

  /// Fourchette de prix conseillée d'après les articles comparables.
  PriceAdvice? priceAdviceFor({required String title, required String category, String? excludeId}) =>
      advisePrice(title: title, category: category, market: _all, excludeId: excludeId);

  void setFilters(ArticleFilters filters) {
    if (filters == _filters) return;
    _filters = filters;
    notifyListeners();
  }

  void resetFilters() => setFilters(ArticleFilters(query: _filters.query));

  void setSearch(String query) => setFilters(_filters.copyWith(query: query));

  void setCategoryFilter(String? category) => setFilters(category == null
      ? _filters.copyWith(clearCategory: true)
      : _filters.copyWith(category: category));

  void toggleFreeOnly() => setFilters(_filters.copyWith(freeOnly: !_filters.freeOnly));

  /// Prix le plus élevé parmi les articles disponibles (borne du curseur).
  double get highestPrice {
    var max = 0.0;
    for (final a in _all) {
      if (a.status != ArticleStatus.done && (a.price ?? 0) > max) max = a.price!;
    }
    return max;
  }

  // --- Position de l'utilisateur ---------------------------------------------

  GeoPoint2? _position;
  GeoPoint2? get userPosition => _position;
  bool locating = false;
  String? locationError;

  /// Demande la position courante. Renvoie true si elle a été obtenue.
  Future<bool> locateUser() async {
    if (locating) return false;
    locating = true;
    locationError = null;
    notifyListeners();
    final result = await _locate();
    locating = false;
    if (result.point != null) {
      _position = result.point;
    } else {
      locationError = result.message;
    }
    notifyListeners();
    return result.point != null;
  }

  /// Distance entre l'utilisateur et [article], si les deux positions sont connues.
  double? distanceKmTo(ArticleModel article) => article.distanceKmFrom(_position);

  // --- Lecture ---------------------------------------------------------------

  ArticleModel? byId(String id) {
    for (final a in _all) {
      if (a.id == id) return a;
    }
    return null;
  }

  List<ArticleModel> favoritesOf(String userId) =>
      _all.where((a) => a.favoritedBy.contains(userId)).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Tous les articles publiés par [userId], du plus récent au plus ancien.
  List<ArticleModel> mine(String userId) =>
      _all.where((a) => a.ownerId == userId).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Future<void> load() async {
    isLoading = true;
    notifyListeners();
    try {
      _all = await _repo.fetchAll(isOnline: _isOnline);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // --- Écriture --------------------------------------------------------------

  /// Copie [files] dans le dossier de l'app et renvoie leurs chemins.
  Future<List<String>> _keepPhotos(List<File> files) async =>
      [for (final f in files) await _photos.keep(f)];

  /// Publie [draft] avec ses photos, enregistrés dans SQLite.
  Future<String> createArticle({
    required ArticleModel draft,
    required List<dynamic> imageFiles, // List<File>
  }) async {
    final files = List<File>.from(imageFiles).take(ArticleModel.maxPhotos).toList();
    final urls = await _keepPhotos(files);
    final toSave = draft.copyWith(imageUrls: urls);
    final id = _uuid.v4();
    await _repo.create(toSave, isOnline: _isOnline, explicitId: id);
    await load();
    return id;
  }

  /// Modifie un article existant : champs du formulaire, photos gardées
  /// ([keptUrls]) et nouvelles photos ([newImages]) ajoutées à la suite.
  Future<void> editArticle(
    ArticleModel original, {
    required String title,
    required String description,
    required String category,
    required double? price,
    required List<String> keptUrls,
    List<File> newImages = const [],
    GeoPoint2? location,
    bool removeLocation = false,
    List<String>? labels,
  }) async {
    final room = ArticleModel.maxPhotos - keptUrls.length;
    final added = await _keepPhotos(newImages.take(room < 0 ? 0 : room).toList());
    final patch = <String, dynamic>{
      'title': title,
      'description': description,
      'category': category,
      'price': price,
      'imageUrls': [...keptUrls, ...added],
      'updatedAt': _clock(),
      if (labels != null) 'labels': labels,
    };
    if (removeLocation) {
      patch['latitude'] = null;
      patch['longitude'] = null;
    } else if (location != null) {
      patch['latitude'] = location.latitude;
      patch['longitude'] = location.longitude;
    }
    await updateArticle(original.id, patch);
  }

  Future<void> updateArticle(String id, Map<String, dynamic> patch) async {
    await _repo.update(id, patch, isOnline: _isOnline);
    await load();
  }

  Future<void> markAsAvailable(String id) =>
      updateArticle(id, {'status': ArticleStatus.available.name});

  Future<void> markAsReserved(String id) =>
      updateArticle(id, {'status': ArticleStatus.reserved.name});

  Future<void> markAsDone(String id) =>
      updateArticle(id, {'status': ArticleStatus.done.name});

  Future<void> deleteArticle(String id) async {
    await _repo.delete(id, isOnline: _isOnline);
    await load();
  }

  Future<void> toggleFavorite(String articleId, String userId) async {
    final article = byId(articleId);
    if (article == null) return;
    final favs = List<String>.from(article.favoritedBy);
    favs.contains(userId) ? favs.remove(userId) : favs.add(userId);
    // Mise à jour immédiate de l'écran, puis écriture dans SQLite.
    _replace(article.copyWith(favoritedBy: favs));
    await _repo.update(articleId, {'favoritedBy': favs}, isOnline: _isOnline);
  }

  final Set<String> _viewed = {};

  /// Compte une vue de [articleId] par [viewerId] (une fois par session, et
  /// jamais pour le propriétaire ni pour un visiteur non connecté).
  Future<void> recordView(String articleId, String? viewerId) async {
    final article = byId(articleId);
    if (article == null || viewerId == null || viewerId == article.ownerId) return;
    if (!_viewed.add(articleId)) return;
    final count = article.viewCount + 1;
    _replace(article.copyWith(viewCount: count));
    try {
      await _repo.update(articleId, {'viewCount': count}, isOnline: _isOnline);
    } catch (_) {
      // Une vue perdue n'est pas grave.
    }
  }

  void _replace(ArticleModel updated) {
    _all = [for (final a in _all) a.id == updated.id ? updated : a];
    notifyListeners();
  }
}
