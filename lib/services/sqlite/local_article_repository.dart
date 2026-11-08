import 'package:uuid/uuid.dart';

import '../../models/article_model.dart';
import 'article_database.dart';
import 'article_store.dart';

/// Articles de Vente & Don **100 % SQLite** : tout est lu et écrit dans la
/// base du téléphone ([ArticleDatabase]), sans Firebase ni réseau.
class LocalArticleRepository implements ArticleStore {
  LocalArticleRepository({Future<ArticleDatabase> Function()? openDatabase})
      : _openDatabase = openDatabase ?? ArticleDatabase.open;

  final Future<ArticleDatabase> Function() _openDatabase;
  static const _uuid = Uuid();

  late final Future<ArticleDatabase> _db = _openDatabase();

  /// Base SQLite ouverte (tests, diagnostic).
  Future<ArticleDatabase> get database => _db;

  @override
  Future<List<ArticleModel>> fetchAll({required bool isOnline}) async => (await _db).all();

  @override
  Future<String> create(ArticleModel item, {required bool isOnline, String? explicitId}) async {
    final id = explicitId ?? _uuid.v4();
    await (await _db).upsert(item.copyWith(id: id));
    return id;
  }

  @override
  Future<void> update(String id, Map<String, dynamic> patch, {required bool isOnline}) async =>
      (await _db).patch(id, patch);

  @override
  Future<void> delete(String id, {required bool isOnline}) async => (await _db).remove(id);
}
