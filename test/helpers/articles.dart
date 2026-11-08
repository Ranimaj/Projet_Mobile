import 'dart:async';
import 'dart:io';

import 'package:campusconnect/models/article_model.dart';
import 'package:campusconnect/services/local_photo_store.dart';
import 'package:campusconnect/services/firestore_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Article de test : seuls les champs utiles au test sont à préciser.
ArticleModel article(
  String id, {
  String ownerId = 'seller-1',
  String ownerName = 'Sami Trabelsi',
  String title = 'Objet',
  String description = 'Un objet en bon état.',
  double? price = 10,
  String category = 'Autre',
  List<String> imageUrls = const [],
  ArticleStatus status = ArticleStatus.available,
  double? latitude,
  double? longitude,
  DateTime? createdAt,
  int viewCount = 0,
  List<String> favoritedBy = const [],
}) {
  return ArticleModel(
    id: id,
    ownerId: ownerId,
    ownerName: ownerName,
    title: title,
    description: description,
    price: price,
    category: category,
    imageUrls: imageUrls,
    status: status,
    latitude: latitude,
    longitude: longitude,
    createdAt: createdAt ?? DateTime(2026, 11, 1),
    viewCount: viewCount,
    favoritedBy: favoritedBy,
  );
}

/// Dépôt en mémoire : remplace Firestore + le stockage local dans les tests du provider
/// et des écrans Vente & Don. Les appels sont enregistrés pour vérification.
class FakeArticleRepo extends Fake implements FirestoreRepository<ArticleModel> {
  final Map<String, Map<String, dynamic>> docs = {};
  final List<(String id, Map<String, dynamic> patch, bool online)> updates = [];
  final List<(String id, bool online)> deletes = [];
  final List<(ArticleModel item, bool online)> creates = [];
  int _next = 0;

  /// Les lectures échouent quand true (réseau coupé sans cache).
  bool failReads = false;

  /// Simule un téléphone « connecté » qui ne joint pas Firebase : les
  /// écritures en ligne ne se terminent jamais.
  bool hangOnline = false;

  Future<void> _maybeHang(bool online) =>
      hangOnline && online ? Completer<void>().future : Future.value();

  FakeArticleRepo([Iterable<ArticleModel> seed = const []]) {
    for (final a in seed) {
      docs[a.id] = a.toMap();
    }
  }

  @override
  Future<List<ArticleModel>> fetchAll({customQuery, required bool isOnline}) async {
    if (failReads) throw StateError('offline');
    return [for (final e in docs.entries) ArticleModel.fromMap(e.key, e.value)];
  }

  @override
  Future<String> create(ArticleModel item, {required bool isOnline, String? explicitId}) async {
    await _maybeHang(isOnline);
    final id = explicitId ?? 'new-${_next++}';
    creates.add((item, isOnline));
    docs[id] = item.toMap();
    return id;
  }

  @override
  Future<void> update(String id, Map<String, dynamic> patch, {required bool isOnline}) async {
    await _maybeHang(isOnline);
    updates.add((id, patch, isOnline));
    docs[id] = {...?docs[id], ...patch};
  }

  @override
  Future<void> delete(String id, {required bool isOnline}) async {
    await _maybeHang(isOnline);
    deletes.add((id, isOnline));
    docs.remove(id);
  }
}

/// Stockage local de photos en mémoire (pas de path_provider dans les tests).
class FakePhotoStore implements LocalPhotoStore {
  final Set<String> files = {};
  final List<String> discarded = [];
  int _next = 0;

  @override
  Future<String> keep(File file) async {
    final path = '/local/photo-${_next++}.jpg';
    files.add(path);
    return path;
  }

  @override
  bool exists(String path) => files.contains(path);

  @override
  File fileOf(String path) => File(path);

  @override
  Future<void> discard(String path) async {
    files.remove(path);
    discarded.add(path);
  }
}
