import 'package:uuid/uuid.dart';

import '../../models/annonce_model.dart';
import 'annonce_database.dart';
import 'annonce_store.dart';

/// Annonces **100 % SQLite** : tout est lu et écrit dans la base du téléphone
/// ([AnnonceDatabase]), sans Firebase ni réseau.
class LocalAnnonceRepository implements AnnonceStore {
  LocalAnnonceRepository({Future<AnnonceDatabase> Function()? openDatabase})
      : _openDatabase = openDatabase ?? AnnonceDatabase.open;

  final Future<AnnonceDatabase> Function() _openDatabase;
  static const _uuid = Uuid();

  late final Future<AnnonceDatabase> _db = _openDatabase();

  /// Base SQLite ouverte (tests, diagnostic).
  Future<AnnonceDatabase> get database => _db;

  @override
  Future<List<AnnonceModel>> fetchAll() async => (await _db).all();

  @override
  Future<AnnonceModel?> byId(String id) async => (await _db).byId(id);

  @override
  Future<String> create(AnnonceModel item, {String? explicitId}) async {
    final id = explicitId ?? _uuid.v4();
    await (await _db).upsert(item, id: id);
    return id;
  }

  @override
  Future<void> update(AnnonceModel item) async => (await _db).upsert(item);

  @override
  Future<void> delete(String id) async => (await _db).remove(id);
}
