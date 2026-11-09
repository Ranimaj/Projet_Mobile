import 'dart:async';

import 'package:uuid/uuid.dart';

import '../core/utils/local_database.dart';

/// Un document lu dans [LocalStore] : son id et une copie de ses données.
class StoredDoc {
  final String id;
  final Map<String, dynamic> data;
  const StoredDoc(this.id, this.data);
}

/// Le document à modifier n'existe pas.
class DocumentNotFound implements Exception {
  final String collection;
  final String id;
  const DocumentNotFound(this.collection, this.id);

  @override
  String toString() => 'DocumentNotFound($collection/$id)';
}

/// Base de données de l'app : des documents JSON rangés par collection
/// (`users`, `events`, `annonces`...), stockés dans SQLite sur le téléphone
/// via [LocalDatabase]. Il n'y a pas de serveur.
///
/// Les lectures sont synchrones (servies par la mémoire) et les écritures
/// mettent la mémoire à jour avant de rendre la main : une suite
/// « lire puis écrire » sans `await` entre les deux est donc atomique, ce qui
/// remplace les transactions.
///
/// Les dates sont stockées comme des `DateTime` (UTC) ; les modèles les
/// relisent avec `parseDate`.
class LocalStore {
  /// [database] remplace la base partagée (tests).
  LocalStore([LocalDatabase? database]) : _override = database;

  final LocalDatabase? _override;
  LocalDatabase get _db => _override ?? LocalDatabase.instance;

  static const _uuid = Uuid();

  /// Nouvel identifiant de document.
  static String newId() => _uuid.v4();

  // --------------------------------------------------------------- Lecture

  Map<String, dynamic>? get(String collection, String id) => _db.readDocument(collection, id);

  bool exists(String collection, String id) => get(collection, id) != null;

  /// Tous les documents de [collection] (ordre non garanti).
  List<StoredDoc> all(String collection) => [
        for (final e in _db.readCollection(collection).entries) StoredDoc(e.key, e.value),
      ];

  /// Documents de [collection] qui vérifient [test].
  List<StoredDoc> where(String collection, bool Function(Map<String, dynamic> data) test) =>
      [for (final d in all(collection)) if (test(d.data)) d];

  /// Premier document qui vérifie [test], ou null.
  StoredDoc? firstWhere(String collection, bool Function(Map<String, dynamic> data) test) {
    for (final d in all(collection)) {
      if (test(d.data)) return d;
    }
    return null;
  }

  // -------------------------------------------------------------- Écriture

  /// Crée ou remplace entièrement le document.
  Future<void> set(String collection, String id, Map<String, dynamic> data) =>
      _db.putDocument(collection, id, data);

  /// Crée ou remplace plusieurs documents de [collection] en une seule
  /// transaction SQLite (import, données de démonstration).
  Future<void> setAll(String collection, Map<String, Map<String, dynamic>> documentsById) =>
      _db.putDocuments(collection, documentsById);

  /// Fusionne [patch] dans le document (créé s'il n'existe pas). Une valeur
  /// `null` dans [patch] efface le champ.
  Future<void> merge(String collection, String id, Map<String, dynamic> patch) =>
      set(collection, id, _apply(get(collection, id) ?? {}, patch));

  /// Comme [merge], mais lève [DocumentNotFound] si le document n'existe pas.
  Future<void> update(String collection, String id, Map<String, dynamic> patch) {
    final current = get(collection, id);
    if (current == null) throw DocumentNotFound(collection, id);
    return set(collection, id, _apply(current, patch));
  }

  Future<void> delete(String collection, String id) => _db.removeDocument(collection, id);

  /// Supprime les documents de [collection] qui vérifient [test] ; renvoie
  /// leur nombre.
  Future<int> deleteWhere(String collection, bool Function(Map<String, dynamic> data) test) async {
    final doomed = where(collection, test);
    for (final d in doomed) {
      await delete(collection, d.id);
    }
    return doomed.length;
  }

  static Map<String, dynamic> _apply(Map<String, dynamic> current, Map<String, dynamic> patch) {
    final next = {...current};
    patch.forEach((key, value) {
      if (value == null) {
        next.remove(key);
      } else {
        next[key] = value;
      }
    });
    return next;
  }

  // ------------------------------------------------------------ Réglages

  /// Petite valeur hors collections (session ouverte, identifiant de
  /// l'appareil...).
  String? getValue(String key) => _db.getValue(key);

  /// Enregistre [value] sous [key] ; null efface la clé.
  Future<void> setValue(String key, String? value) => _db.setValue(key, value);

  // --------------------------------------------------------- Temps réel

  /// Les documents de [collection] maintenant, puis à chaque modification.
  Stream<List<StoredDoc>> watch(String collection) =>
      _watch(collection, () => all(collection));

  /// Le document maintenant (null s'il n'existe pas), puis à chaque
  /// modification de sa collection.
  Stream<Map<String, dynamic>?> watchDoc(String collection, String id) =>
      _watch(collection, () => get(collection, id));

  Stream<T> _watch<T>(String collection, T Function() read) {
    late StreamController<T> controller;
    StreamSubscription<String>? sub;
    controller = StreamController<T>(
      onListen: () {
        controller.add(read());
        sub = _db.changes.where((c) => c == collection).listen((_) {
          if (!controller.isClosed) controller.add(read());
        });
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }
}

/// Relit une date stockée : `DateTime` (base locale), chaîne ISO 8601 ou
/// millisecondes. Renvoie l'heure locale, ou null.
DateTime? parseDate(Object? value) {
  if (value is DateTime) return value.toLocal();
  if (value is String) return DateTime.tryParse(value)?.toLocal();
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}
