import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Une action de la file hors-ligne telle que stockée (forme brute).
/// [OfflineQueueService] la transforme en `QueuedAction`.
@immutable
class QueueRecord {
  final String id;

  /// Nom de `QueueActionType` : create, update, delete, uploadStudentCard.
  final String type;
  final String collection;
  final String docId;
  final Map<String, dynamic> payload;
  final DateTime queuedAt;

  /// Compteur en mémoire (non persisté), incrémenté à chaque modification du
  /// payload : la synchro sait ainsi si l'action a changé pendant l'envoi.
  final int revision;

  const QueueRecord({
    required this.id,
    required this.type,
    required this.collection,
    required this.docId,
    required this.payload,
    required this.queuedAt,
    this.revision = 0,
  });
}

/// Stockage local unique de l'app (SQLite) : cache des collections, file
/// d'attente hors-ligne et petites préférences.
///
/// Tout est chargé en mémoire UNE fois à l'ouverture ([open], dans main()).
/// Ensuite :
/// - les lectures sont synchrones (servies par la mémoire) ;
/// - une écriture met d'abord la mémoire à jour, immédiatement, puis
///   enregistre dans SQLite en arrière-plan ; les écritures SQLite passent
///   une par une, dans l'ordre des appels.
///
/// Une seule instance partagée ([instance]) : tous les LocalCacheService et
/// OfflineQueueService de l'app voient les mêmes données.
class LocalDatabase {
  LocalDatabase._(this._db);

  static const String fileName = 'campusconnect.db';
  static const int schemaVersion = 1;

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
      options: OpenDatabaseOptions(version: schemaVersion, onCreate: _createSchema),
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
        CREATE TABLE offline_queue (
          id         TEXT PRIMARY KEY,
          type       TEXT NOT NULL
                     CHECK (type IN ('create', 'update', 'delete', 'uploadStudentCard')),
          collection TEXT NOT NULL,
          doc_id     TEXT NOT NULL,
          payload    TEXT NOT NULL,
          queued_at  INTEGER NOT NULL
        )''')
      ..execute('CREATE INDEX idx_queue_doc ON offline_queue (collection, doc_id)')
      ..execute('CREATE INDEX idx_queue_time ON offline_queue (queued_at)')
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

  /// File hors-ligne, dans l'ordre (queued_at puis ordre d'ajout).
  final Map<String, QueueRecord> _queue = {};
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
    for (final row in await _db.query('offline_queue', orderBy: 'queued_at, rowid')) {
      try {
        final record = QueueRecord(
          id: row['id'] as String,
          type: row['type'] as String,
          collection: row['collection'] as String,
          docId: row['doc_id'] as String,
          payload: _decodeMap(row['payload'] as String),
          queuedAt: DateTime.fromMillisecondsSinceEpoch(row['queued_at'] as int),
        );
        _queue[record.id] = record;
      } catch (e) {
        debugPrint('LocalDatabase : action hors-ligne illisible ignorée : $e');
      }
    }
    for (final row in await _db.query('kv')) {
      _kv[row['key'] as String] = row['value'] as String;
    }
  }

  /// Attend que toutes les écritures déjà demandées soient dans SQLite.
  Future<void> flush() => _tail;

  /// Termine les écritures en cours puis ferme la base.
  Future<void> close() async {
    await flush();
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

  /// Remplace tout le cache de [collection].
  Future<void> replaceCollection(String collection, Map<String, Map<String, dynamic>> documentsById) {
    final encoded = {for (final e in documentsById.entries) e.key: _encodeMap(e.value)};
    _cache[collection] = {for (final e in encoded.entries) e.key: _decodeMap(e.value)};
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
    final now = DateTime.now().millisecondsSinceEpoch;
    return _write((db) => db.insert(
          'cache_documents',
          {'collection': collection, 'doc_id': id, 'data': json, 'updated_at': now},
          conflictAlgorithm: ConflictAlgorithm.replace,
        ));
  }

  Future<void> removeDocument(String collection, String id) {
    _cache[collection]?.remove(id);
    return _write((db) =>
        db.delete('cache_documents', where: 'collection = ? AND doc_id = ?', whereArgs: [collection, id]));
  }

  // ---------------------------------------------------------- File d'attente

  int get queueLength => _queue.length;

  /// Actions en attente, dans l'ordre (payloads copiés).
  List<QueueRecord> get queuedActions => [for (final r in _queue.values) _copyRecord(r)];

  /// Version actuelle de l'action [id] (copie), ou null si elle n'est plus en file.
  QueueRecord? queued(String id) {
    final r = _queue[id];
    return r == null ? null : _copyRecord(r);
  }

  static QueueRecord _copyRecord(QueueRecord r) => QueueRecord(
        id: r.id,
        type: r.type,
        collection: r.collection,
        docId: r.docId,
        payload: _copy(r.payload),
        queuedAt: r.queuedAt,
        revision: r.revision,
      );

  /// Ajoute une action, en retirant d'abord les actions [replacing], le tout
  /// dans une seule transaction SQLite. La mémoire est à jour au retour de
  /// l'appel ; le Future se termine quand SQLite l'est aussi.
  Future<void> addQueued({
    required String id,
    required String type,
    required String collection,
    required String docId,
    required Map<String, dynamic> payload,
    required DateTime queuedAt,
    Iterable<String> replacing = const [],
  }) {
    final json = _encodeMap(payload);
    final ms = queuedAt.millisecondsSinceEpoch;
    final removed = [for (final old in replacing) if (_queue.remove(old) != null) old];
    _queue[id] = QueueRecord(
      id: id,
      type: type,
      collection: collection,
      docId: docId,
      payload: _decodeMap(json),
      queuedAt: DateTime.fromMillisecondsSinceEpoch(ms),
    );
    return _write((db) => db.transaction((txn) async {
          for (final old in removed) {
            await txn.delete('offline_queue', where: 'id = ?', whereArgs: [old]);
          }
          await txn.insert('offline_queue', {
            'id': id,
            'type': type,
            'collection': collection,
            'doc_id': docId,
            'payload': json,
            'queued_at': ms,
          });
        }));
  }

  /// Remplace le payload de plusieurs actions d'un coup (une transaction).
  /// Les ids absents de la file sont ignorés.
  Future<void> updateQueuedPayloads(Map<String, Map<String, dynamic>> payloadById) {
    final encoded = <String, String>{};
    for (final e in payloadById.entries) {
      final current = _queue[e.key];
      if (current == null) continue;
      final json = _encodeMap(e.value);
      encoded[e.key] = json;
      _queue[e.key] = QueueRecord(
        id: current.id,
        type: current.type,
        collection: current.collection,
        docId: current.docId,
        payload: _decodeMap(json),
        queuedAt: current.queuedAt,
        revision: current.revision + 1,
      );
    }
    if (encoded.isEmpty) return _tail;
    // UPDATE (et non REPLACE) : la ligne garde sa place dans l'ordre d'ajout.
    return _write((db) => db.transaction((txn) async {
          for (final e in encoded.entries) {
            await txn.update('offline_queue', {'payload': e.value}, where: 'id = ?', whereArgs: [e.key]);
          }
        }));
  }

  Future<void> removeQueued(Iterable<String> ids) {
    final removed = [for (final id in ids) if (_queue.remove(id) != null) id];
    if (removed.isEmpty) return _tail;
    return _write((db) => db.transaction((txn) async {
          for (final id in removed) {
            await txn.delete('offline_queue', where: 'id = ?', whereArgs: [id]);
          }
        }));
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
