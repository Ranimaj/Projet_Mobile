import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/article_search.dart';
import '../core/utils/geo.dart';
import '../models/article_model.dart';
import '../services/firestore_repository.dart';
import '../services/local_photo_store.dart';
import '../services/location_service.dart';
import '../services/storage_service.dart';

/// Gestion Vente & Don — CRUD complet, recherche intelligente avec filtres
/// combinés (texte, catégorie, gratuit, prix, distance, tri), upload
/// multi-images compressées, favoris et compteur de vues. Fonctionne
/// hors-ligne (BNF3) grâce au [FirestoreRepository], photos comprises : sans
/// réseau elles restent sur le téléphone puis partent au retour de la
/// connexion ([syncPendingPhotos]).
class ArticleProvider extends ChangeNotifier {
  ArticleProvider({
    FirestoreRepository<ArticleModel>? repository,
    StorageService? storage,
    LocationLookup? locate,
    DateTime Function()? clock,
    LocalPhotoStore? photos,
    Future<void> Function(String docId, Map<String, dynamic> patch)? patchQueued,
    Duration networkTimeout = const Duration(seconds: 12),
    Duration uploadTimeout = const Duration(seconds: 45),
  })  : _repoOverride = repository,
        _storageOverride = storage,
        _locate = locate ?? currentLocation,
        _clock = clock ?? DateTime.now,
        _photosOverride = photos,
        _patchQueuedOverride = patchQueued,
        _networkTimeout = networkTimeout,
        _uploadTimeout = uploadTimeout;

  final FirestoreRepository<ArticleModel>? _repoOverride;
  final StorageService? _storageOverride;
  final LocationLookup _locate;
  final DateTime Function() _clock;
  final LocalPhotoStore? _photosOverride;
  final Future<void> Function(String docId, Map<String, dynamic> patch)? _patchQueuedOverride;
  final Duration _networkTimeout;
  final Duration _uploadTimeout;
  static const _uuid = Uuid();

  // Créés à la première utilisation : les tests qui injectent des doublures
  // ne touchent jamais Firebase.
  late final FirestoreRepository<ArticleModel> _repo = _repoOverride ??
      FirestoreRepository<ArticleModel>(
        collectionName: AppConstants.articlesCollection,
        cacheBoxName: AppConstants.hiveArticlesBox,
        fromMap: ArticleModel.fromMap,
        toMap: (a) => a.toMap(),
      );
  late final StorageService _storage = _storageOverride ?? StorageService();
  late final LocalPhotoStore _photos = _photosOverride ?? LocalPhotoStore();

  /// Met à jour les actions encore en file d'attente pour un article.
  Future<void> _patchQueued(String docId, Map<String, dynamic> patch) {
    final override = _patchQueuedOverride;
    if (override != null) return override(docId, patch);
    return _repo.queue.patchPending(AppConstants.articlesCollection, docId, patch);
  }

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  /// Appelé par main.dart à chaque changement de réseau. Au retour de la
  /// connexion, les photos publiées hors-ligne partent vers Storage.
  void updateConnectivity(bool online) {
    final cameBack = online && !_isOnline;
    _isOnline = online;
    if (cameBack) unawaited(syncPendingPhotos());
  }

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

  /// Articles visibles dans la liste : non terminés, filtrés et triés.
  List<ArticleModel> get items => filterArticles(
        _all.where((a) => a.status != ArticleStatus.done),
        _filters,
        from: _position,
      );

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
    if (_isOnline && _all.any(_hasPhotosToSend)) unawaited(syncPendingPhotos());
  }

  // --- Écriture --------------------------------------------------------------
  //
  // Un téléphone peut se croire « en ligne » (Wi-Fi connecté) sans joindre
  // Firebase. Chaque écriture en ligne a donc un délai maximal : passé ce
  // délai, elle bascule dans la file d'attente hors-ligne (même identifiant de
  // document, donc pas de doublon quand Firestore rattrape son retard).

  Future<T> _onlineOrQueue<T>(Future<T> Function(bool online) write) async {
    if (!_isOnline) return write(false);
    try {
      return await write(true).timeout(_networkTimeout);
    } on TimeoutException {
      return write(false);
    }
  }

  /// Envoie [files] dans Storage, ou les garde sur le téléphone si le réseau
  /// est absent ou trop lent. Renvoie URL distantes ou chemins locaux, dans
  /// l'ordre de [files].
  Future<List<String>> _uploadOrKeep(List<File> files) async {
    if (files.isEmpty) return const [];
    if (_isOnline) {
      try {
        return await _storage.uploadImages(files, folder: 'articles').timeout(_uploadTimeout);
      } catch (_) {
        // Réseau injoignable : on garde les photos en local.
      }
    }
    return [for (final f in files) await _photos.keep(f)];
  }

  /// Publie [draft] avec ses photos (compressées avant envoi). Sans réseau,
  /// l'article et ses photos sont gardés sur le téléphone, affichés tout de
  /// suite, puis envoyés automatiquement au retour de la connexion.
  Future<String> createArticle({
    required ArticleModel draft,
    required List<dynamic> imageFiles, // List<File>
  }) async {
    final files = List<File>.from(imageFiles).take(ArticleModel.maxPhotos).toList();
    final urls = await _uploadOrKeep(files);
    final toSave = draft.copyWith(imageUrls: urls);
    final id = _uuid.v4();
    await _onlineOrQueue((online) => _repo.create(toSave, isOnline: online, explicitId: id));
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
  }) async {
    final room = ArticleModel.maxPhotos - keptUrls.length;
    final added = await _uploadOrKeep(newImages.take(room < 0 ? 0 : room).toList());
    final patch = <String, dynamic>{
      'title': title,
      'description': description,
      'category': category,
      'price': price,
      'imageUrls': [...keptUrls, ...added],
      'updatedAt': _clock(),
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
    await _onlineOrQueue((online) => _repo.update(id, patch, isOnline: online));
    await load();
  }

  // --- Photos en attente -----------------------------------------------------

  /// Article de ce téléphone dont des photos attendent l'envoi.
  bool _hasPhotosToSend(ArticleModel a) =>
      a.imageUrls.any((u) => isLocalImage(u) && _photos.exists(u));

  /// Nombre d'articles dont les photos attendent le réseau.
  int get pendingPhotoArticles => _all.where(_hasPhotosToSend).length;

  bool _syncingPhotos = false;

  /// Envoie les photos gardées hors-ligne puis remplace leurs chemins locaux
  /// par les URL Storage (dans Firestore, le cache et la file d'attente).
  /// Renvoie le nombre d'articles mis à jour. Sans danger si rien n'attend.
  Future<int> syncPendingPhotos() async {
    if (!_isOnline || _syncingPhotos) return 0;
    _syncingPhotos = true;
    var done = 0;
    try {
      for (final a in List.of(_all)) {
        if (!_hasPhotosToSend(a)) continue;
        final locals = [for (final u in a.imageUrls) if (isLocalImage(u) && _photos.exists(u)) u];
        final List<String> remote;
        try {
          remote = await _storage
              .uploadImages([for (final p in locals) _photos.fileOf(p)], folder: 'articles')
              .timeout(_uploadTimeout);
        } catch (_) {
          break; // toujours pas de réseau : on réessaiera plus tard
        }
        final byLocal = {for (var i = 0; i < locals.length; i++) locals[i]: remote[i]};
        // Les chemins locaux introuvables (autre appareil) sont retirés.
        final urls = [
          for (final u in a.imageUrls)
            if (!isLocalImage(u)) u else if (byLocal[u] != null) byLocal[u]!,
        ];
        final patch = {'imageUrls': urls};
        await _patchQueued(a.id, patch);
        await _onlineOrQueue((online) => _repo.update(a.id, patch, isOnline: online));
        _replace(a.copyWith(imageUrls: urls));
        for (final p in locals) {
          await _photos.discard(p);
        }
        done++;
      }
    } finally {
      _syncingPhotos = false;
    }
    return done;
  }

  Future<void> markAsAvailable(String id) =>
      updateArticle(id, {'status': ArticleStatus.available.name});

  Future<void> markAsReserved(String id) =>
      updateArticle(id, {'status': ArticleStatus.reserved.name});

  Future<void> markAsDone(String id) =>
      updateArticle(id, {'status': ArticleStatus.done.name});

  Future<void> deleteArticle(String id) async {
    await _onlineOrQueue((online) => _repo.delete(id, isOnline: online));
    await load();
  }

  Future<void> toggleFavorite(String articleId, String userId) async {
    final article = byId(articleId);
    if (article == null) return;
    final favs = List<String>.from(article.favoritedBy);
    favs.contains(userId) ? favs.remove(userId) : favs.add(userId);
    // Mise à jour immédiate de l'écran, puis écriture (ou file d'attente).
    _replace(article.copyWith(favoritedBy: favs));
    await _onlineOrQueue((online) => _repo.update(articleId, {'favoritedBy': favs}, isOnline: online));
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
      await _onlineOrQueue((online) => _repo.update(articleId, {'viewCount': count}, isOnline: online));
    } catch (_) {
      // Une vue perdue n'est pas grave.
    }
  }

  void _replace(ArticleModel updated) {
    _all = [for (final a in _all) a.id == updated.id ? updated : a];
    notifyListeners();
  }
}
