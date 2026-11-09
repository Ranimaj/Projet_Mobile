import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Stockage local unique de l'app (SQLite) : toutes les données (documents
/// rangés par collection) et petites préférences. Il n'y a pas de serveur :
/// cette base est la seule source de vérité.
///
/// Tout est chargé en mémoire UNE fois à l'ouverture ([open], dans main()).
/// Ensuite :
/// - les lectures sont synchrones (servies par la mémoire) ;
/// - une écriture met d'abord la mémoire à jour, immédiatement, puis
///   enregistre dans SQLite en arrière-plan ; les écritures SQLite passent
///   une par une, dans l'ordre des appels.
///
/// Une seule instance partagée ([instance]) : tous les [LocalStore] de l'app
/// voient les mêmes données.
class LocalDatabase {
  LocalDatabase._(this._db);

  static const String fileName = 'campusconnect.db';
  /// 1 : + file hors-ligne (abandonnée en 2, plus de serveur).
  static const int schemaVersion = 2;

  /// Marqueur d'une date dans le JSON stocké : `{"$date": "<ISO UTC>"}`.
  static const String dateMarker = r'$date';

  static LocalDatabase? _instance;

  /// Vrai une fois [open] terminé.
  static bool get isOpen => _instance != null;

  /// Le stockage partagé. Lève une [StateError] si [open] n'a pas été appelé
  /// (les appelants qui le tolèrent attrapent cette erreur).
  static LocalDatabase get instance {
    final store = _instance;
    if (store == null) throw StateError('LocalDatabase.open() n\'a pas été appelé');
    return store;
  }

  /// Ouvre (ou crée) la base puis charge tout en mémoire. [factory] et [path]
  /// sont remplaçables dans les tests (sqflite_common_ffi). Rouvrir ferme
  /// d'abord l'instance précédente.
  static Future<LocalDatabase> open({DatabaseFactory? factory, String? path}) async {
    await _instance?.close();
    final dbFactory = factory ?? databaseFactorySqflitePlugin;
    final dbPath = path ?? p.join(await dbFactory.getDatabasesPath(), fileName);
    final db = await dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onCreate: _createSchema,
        onUpgrade: (db, from, _) async {
          if (from < 2) await db.execute('DROP TABLE IF EXISTS offline_queue');
        },
      ),
    );
    final store = LocalDatabase._(db);
    await store._loadAll();
    return _instance = store;
  }

  /// Boîtes des anciennes versions de l'app (stockage Hive, abandonné).
  static const List<String> legacyHiveBoxes = [
    'articles_box',
    'annonces_box',
    'events_box',
    'jobs_box',
    'applications_box',
    'user_box',
    'offline_queue_box',
    'prefs_box',
  ];

  /// Supprime les fichiers `.hive` / `.lock` laissés par les anciennes
  /// versions dans le dossier documents ([dir], remplaçable dans les tests).
  /// Leurs données ne sont pas reprises (décision du projet). Ne lève jamais.
  static Future<void> deleteLegacyHiveFiles({Directory? dir}) async {
    try {
      final base = dir ?? await getApplicationDocumentsDirectory();
      for (final box in legacyHiveBoxes) {
        for (final ext in const ['hive', 'lock']) {
          final file = File(p.join(base.path, '$box.$ext'));
          if (await file.exists()) await file.delete();
        }
      }
    } catch (e) {
      debugPrint('LocalDatabase : nettoyage des anciens fichiers Hive ignoré : $e');
    }
  }

  static Future<void> _createSchema(Database db, int version) async {
    final batch = db.batch()
      ..execute('''
        CREATE TABLE cache_documents (
          collection TEXT NOT NULL,
          doc_id     TEXT NOT NULL,
          data       TEXT NOT NULL,
          updated_at INTEGER NOT NULL,
          PRIMARY KEY (collection, doc_id)
        )''')
      ..execute('''
        CREATE TABLE kv (
          key   TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )''');
    await batch.commit(noResult: true);
  }

  final Database _db;

  /// collection → id du document → données.
  final Map<String, Map<String, Map<String, dynamic>>> _cache = {};

  final Map<String, String> _kv = {};

  /// Dernière écriture SQLite programmée : la suivante l'attend.
  Future<void> _tail = Future<void>.value();

  Future<void> _loadAll() async {
    for (final row in await _db.query('cache_documents')) {
      try {
        _cache.putIfAbsent(row['collection'] as String, () => {})[row['doc_id'] as String] =
            _decodeMap(row['data'] as String);
      } catch (e) {
        debugPrint('LocalDatabase : document de cache illisible ignoré : $e');
      }
    }
    for (final row in await _db.query('kv')) {
      _kv[row['key'] as String] = row['value'] as String;
    }
  }

  /// Attend que toutes les écritures déjà demandées soient dans SQLite.
  Future<void> flush() => _tail;

  /// Nom de chaque collection modifiée, juste après la mise à jour de la
  /// mémoire (les lectures voient déjà la nouvelle valeur).
  final StreamController<String> _changes = StreamController<String>.broadcast(sync: true);
  Stream<String> get changes => _changes.stream;

  void _changed(String collection) {
    if (!_changes.isClosed) _changes.add(collection);
  }

  /// Termine les écritures en cours puis ferme la base.
  Future<void> close() async {
    await flush();
    await _changes.close();
    await _db.close();
    if (identical(_instance, this)) _instance = null;
  }

  /// Programme [op] après les écritures précédentes. Le Future renvoyé ne
  /// lève jamais : un échec est journalisé (la mémoire reste à jour et la
  /// donnée sera réécrite à la prochaine modification).
  Future<void> _write(Future<void> Function(Database db) op) {
    final run = _tail.then((_) => op(_db));
    return _tail = run.catchError((Object e) {
      debugPrint('LocalDatabase : écriture SQLite échouée : $e');
    });
  }

  // ------------------------------------------------------------- Codec JSON

  /// Rend [value] encodable en JSON : chaque DateTime devient
  /// `{"$date": "<ISO UTC>"}`, récursivement (maps et listes).
  static Object? encodeValue(Object? value) {
    if (value is DateTime) return {dateMarker: value.toUtc().toIso8601String()};
    if (value is Map) {
      return <String, dynamic>{for (final e in value.entries) e.key.toString(): encodeValue(e.value)};
    }
    if (value is Iterable) return [for (final v in value) encodeValue(v)];
    return value;
  }

  /// Inverse de [encodeValue] : chaque `{"$date": ...}` redevient un DateTime
  /// (UTC), y compris dans les listes et les maps imbriquées.
  static Object? decodeValue(Object? value) {
    if (value is Map) {
      if (value.length == 1 && value[dateMarker] is String) {
        final date = DateTime.tryParse(value[dateMarker] as String);
        if (date != null) return date;
      }
      return <String, dynamic>{for (final e in value.entries) e.key.toString(): decodeValue(e.value)};
    }
    if (value is List) return [for (final v in value) decodeValue(v)];
    return value;
  }

  /// JSON stocké pour [map]. Lève (JsonUnsupportedObjectError) tout de suite,
  /// dans l'appel, si une valeur n'est pas stockable.
  static String _encodeMap(Map<String, dynamic> map) => jsonEncode(encodeValue(map));

  static Map<String, dynamic> _decodeMap(String json) =>
      decodeValue(jsonDecode(json)) as Map<String, dynamic>;

  /// Copie profonde : un appelant qui modifie le résultat ne touche pas au stockage.
  static Map<String, dynamic> _copy(Map<String, dynamic> map) =>
      decodeValue(encodeValue(map)) as Map<String, dynamic>;

  // ------------------------------------------------------------------ Cache

  /// Documents en cache de [collection] (copies).
  Map<String, Map<String, dynamic>> readCollection(String collection) => {
        for (final e in (_cache[collection] ?? const <String, Map<String, dynamic>>{}).entries)
          e.key: _copy(e.value),
      };

  /// Un document de [collection] (copie), ou null s'il n'existe pas.
  Map<String, dynamic>? readDocument(String collection, String id) {
    final doc = _cache[collection]?[id];
    return doc == null ? null : _copy(doc);
  }

  /// Remplace tout le contenu de [collection].
  Future<void> replaceCollection(String collection, Map<String, Map<String, dynamic>> documentsById) {
    final encoded = {for (final e in documentsById.entries) e.key: _encodeMap(e.value)};
    _cache[collection] = {for (final e in encoded.entries) e.key: _decodeMap(e.value)};
    _changed(collection);
    final now = DateTime.now().millisecondsSinceEpoch;
    return _write((db) => db.transaction((txn) async {
          await txn.delete('cache_documents', where: 'collection = ?', whereArgs: [collection]);
          final batch = txn.batch();
          for (final e in encoded.entries) {
            batch.insert('cache_documents',
                {'collection': collection, 'doc_id': e.key, 'data': e.value, 'updated_at': now});
          }
          await batch.commit(noResult: true);
        }));
  }

  /// Ajoute ou remplace un document du cache.
  Future<void> putDocument(String collection, String id, Map<String, dynamic> data) {
    final json = _encodeMap(data);
    _cache.putIfAbsent(collection, () => {})[id] = _decodeMap(json);
    _changed(collection);
    final now = DateTime.now().millisecondsSinceEpoch;
    return _write((db) => db.insert(
          'cache_documents',
          {'collection': collection, 'doc_id': id, 'data': json, 'updated_at': now},
          conflictAlgorithm: ConflictAlgorithm.replace,
        ));
  }

  /// Ajoute ou remplace plusieurs documents de [collection] en une seule
  /// transaction SQLite (une seule notification de changement).
  Future<void> putDocuments(String collection, Map<String, Map<String, dynamic>> documentsById) {
    if (documentsById.isEmpty) return _tail;
    final encoded = {for (final e in documentsById.entries) e.key: _encodeMap(e.value)};
    final docs = _cache.putIfAbsent(collection, () => {});
    for (final e in encoded.entries) {
      docs[e.key] = _decodeMap(e.value);
    }
    _changed(collection);
    final now = DateTime.now().millisecondsSinceEpoch;
    return _write((db) => db.transaction((txn) async {
          final batch = txn.batch();
          for (final e in encoded.entries) {
            batch.insert(
              'cache_documents',
              {'collection': collection, 'doc_id': e.key, 'data': e.value, 'updated_at': now},
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          await batch.commit(noResult: true);
        }));
  }

  Future<void> removeDocument(String collection, String id) {
    if (_cache[collection]?.remove(id) != null) _changed(collection);
    return _write((db) =>
        db.delete('cache_documents', where: 'collection = ? AND doc_id = ?', whereArgs: [collection, id]));
  }

  // ------------------------------------------------------------ Préférences

  String? getValue(String key) => _kv[key];

  /// Enregistre [value] sous [key] ; null efface la clé.
  Future<void> setValue(String key, String? value) {
    if (value == null) {
      _kv.remove(key);
      return _write((db) => db.delete('kv', where: 'key = ?', whereArgs: [key]));
    }
    _kv[key] = value;
    return _write((db) =>
        db.insert('kv', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace));
  }
}
