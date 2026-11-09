import 'dart:async';

import 'package:campusconnect/services/local_store.dart';

/// [LocalStore] entièrement en mémoire pour les tests d'écran admin : les
/// écritures SQLite réelles ne se terminent pas dans le temps simulé de
/// testWidgets, celles-ci se terminent immédiatement. Mêmes règles que le
/// vrai magasin (copies, `update` qui lève, flux par collection).
class MemoryLocalStore extends LocalStore {
  final Map<String, Map<String, Map<String, dynamic>>> _docs = {};
  final Map<String, String> _values = {};
  final StreamController<String> _changes =
      StreamController<String>.broadcast(sync: true);

  static Map<String, dynamic> _copy(Map<String, dynamic> m) => {
        for (final e in m.entries)
          e.key: e.value is Map
              ? _copy(Map<String, dynamic>.from(e.value as Map))
              : e.value,
      };

  @override
  Map<String, dynamic>? get(String collection, String id) {
    final doc = _docs[collection]?[id];
    return doc == null ? null : _copy(doc);
  }

  @override
  List<StoredDoc> all(String collection) => [
        for (final e
            in (_docs[collection] ?? const <String, Map<String, dynamic>>{})
                .entries)
          StoredDoc(e.key, _copy(e.value)),
      ];

  @override
  Future<void> set(String collection, String id, Map<String, dynamic> data) {
    (_docs[collection] ??= {})[id] = _copy(data);
    _changes.add(collection);
    return Future.value();
  }

  @override
  Future<void> delete(String collection, String id) {
    _docs[collection]?.remove(id);
    _changes.add(collection);
    return Future.value();
  }

  @override
  String? getValue(String key) => _values[key];

  @override
  Future<void> setValue(String key, String? value) {
    value == null ? _values.remove(key) : _values[key] = value;
    return Future.value();
  }

  @override
  Stream<List<StoredDoc>> watch(String collection) =>
      _watch(collection, () => all(collection));

  @override
  Stream<Map<String, dynamic>?> watchDoc(String collection, String id) =>
      _watch(collection, () => get(collection, id));

  Stream<T> _watch<T>(String collection, T Function() read) {
    late StreamController<T> controller;
    StreamSubscription<String>? sub;
    controller = StreamController<T>(
      onListen: () {
        controller.add(read());
        sub = _changes.stream
            .where((c) => c == collection)
            .listen((_) => controller.add(read()));
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }
}
