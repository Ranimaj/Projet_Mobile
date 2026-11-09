import 'local_store.dart';

/// Dépôt générique d'une collection (Annonces, Stage & Emploi...) stockée
/// dans la base SQLite du téléphone ([LocalStore]). Pas de réseau : tout
/// fonctionne de la même façon en ligne et hors-ligne.
class LocalRepository<T> {
  LocalRepository({
    required this.collectionName,
    required this.fromMap,
    required this.toMap,
    LocalStore? store,
  }) : _store = store ?? LocalStore();

  final String collectionName;
  final T Function(String id, Map<String, dynamic> map) fromMap;
  final Map<String, dynamic> Function(T item) toMap;
  final LocalStore _store;

  List<T> fetchAll() => [for (final d in _store.all(collectionName)) fromMap(d.id, d.data)];

  T? fetch(String id) {
    final data = _store.get(collectionName, id);
    return data == null ? null : fromMap(id, data);
  }

  /// La collection maintenant, puis à chaque modification.
  Stream<List<T>> watchAll() =>
      _store.watch(collectionName).map((docs) => [for (final d in docs) fromMap(d.id, d.data)]);

  /// Crée [item] (id tiré au hasard sauf [explicitId]) et renvoie son id.
  Future<String> create(T item, {String? explicitId}) async {
    final id = explicitId ?? LocalStore.newId();
    await _store.set(collectionName, id, toMap(item));
    return id;
  }

  Future<void> update(String id, Map<String, dynamic> patch) => _store.update(collectionName, id, patch);

  Future<void> delete(String id) => _store.delete(collectionName, id);
}
