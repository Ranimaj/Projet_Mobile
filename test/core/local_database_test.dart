import 'dart:convert';
import 'dart:io';

import 'package:campusconnect/core/utils/local_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/local_db.dart';

void main() {
  late Directory dir;
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('local_db_test');
    path = p.join(dir.path, 'test.db');
  });

  tearDown(() async {
    await closeTestDatabase();
    await dir.delete(recursive: true);
  });

  /// Ferme puis rouvre le même fichier : seul ce qui est dans SQLite revient.
  Future<LocalDatabase> reload() async {
    await LocalDatabase.instance.close();
    return openTestDatabase(path: path);
  }

  group('ouverture', () {
    test('instance avant open : StateError', () async {
      await closeTestDatabase();
      expect(LocalDatabase.isOpen, isFalse);
      expect(() => LocalDatabase.instance, throwsStateError);
    });

    test('une seule instance partagée', () async {
      final store = await openTestDatabase();
      expect(LocalDatabase.isOpen, isTrue);
      expect(identical(LocalDatabase.instance, store), isTrue);
    });

    test('schéma : tables et version', () async {
      await openTestDatabase(path: path);
      await LocalDatabase.instance.close();
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(path);
      addTearDown(db.close);
      final names = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type IN ('table','index')"))
          .map((r) => r['name'])
          .toSet();
      expect(names, containsAll(['cache_documents', 'kv']));
      expect(names, isNot(contains('offline_queue')));
      expect(await db.getVersion(), LocalDatabase.schemaVersion);
    });

    test('mise à jour depuis la version 1 : documents gardés, file hors-ligne supprimée', () async {
      sqfliteFfiInit();
      final v1 = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) async {
              await db.execute('CREATE TABLE cache_documents (collection TEXT NOT NULL, doc_id TEXT NOT NULL, '
                  'data TEXT NOT NULL, updated_at INTEGER NOT NULL, PRIMARY KEY (collection, doc_id))');
              await db.execute('CREATE TABLE offline_queue (id TEXT PRIMARY KEY)');
              await db.execute('CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
            },
          ));
      await v1.insert('cache_documents', {'collection': 'users', 'doc_id': 'u1', 'data': '{"fullName":"Amel"}', 'updated_at': 0});
      await v1.close();

      final store = await openTestDatabase(path: path);
      expect(store.readDocument('users', 'u1'), {'fullName': 'Amel'});
      await store.close();
      final db = await databaseFactoryFfi.openDatabase(path);
      addTearDown(db.close);
      final tables = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'")).map((r) => r['name']);
      expect(tables, isNot(contains('offline_queue')));
    });

    test('une ligne illisible est ignorée au chargement, sans crash', () async {
      await openTestDatabase(path: path);
      await LocalDatabase.instance.putDocument('events_box', 'ok', {'title': 'A'});
      await LocalDatabase.instance.close();
      final db = await databaseFactoryFfi.openDatabase(path);
      await db.insert('cache_documents',
          {'collection': 'events_box', 'doc_id': 'bad', 'data': '{pas du json', 'updated_at': 0});
      await db.close();

      final store = await openTestDatabase(path: path);
      expect(store.readCollection('events_box').keys, ['ok']);
    });
  });

  group('codec des dates', () {
    test('aller-retour récursif (maps, listes, maps dans des listes)', () {
      final local = DateTime(2026, 11, 8, 14, 30);
      final value = {
        'at': local,
        'list': [DateTime.utc(2026, 1, 1), 'texte', 3, null],
        'nested': {
          'deep': [
            {'when': DateTime.utc(2025, 12, 31, 23, 59, 59, 999)},
          ],
        },
      };
      final encoded = LocalDatabase.encodeValue(value) as Map<String, dynamic>;
      expect(encoded['at'], {r'$date': local.toUtc().toIso8601String()});

      final decoded = LocalDatabase.decodeValue(encoded) as Map<String, dynamic>;
      expect(decoded['at'], isA<DateTime>());
      expect((decoded['at'] as DateTime).isAtSameMomentAs(local), isTrue);
      expect((decoded['list'] as List)[0], DateTime.utc(2026, 1, 1));
      expect((decoded['list'] as List).sublist(1), ['texte', 3, null]);
      final deep = ((decoded['nested'] as Map)['deep'] as List).single as Map;
      expect(deep['when'], DateTime.utc(2025, 12, 31, 23, 59, 59, 999));
    });

    test('une map ordinaire reste une map', () {
      expect(LocalDatabase.decodeValue({r'$date': 12}), {r'$date': 12});
      expect(LocalDatabase.decodeValue({r'$date': 'x', 'b': 1}), {r'$date': 'x', 'b': 1});
    });
  });

  group('documents', () {
    test('lecture immédiate (mémoire) puis persistance', () async {
      final store = await openTestDatabase(path: path);
      // Pas d'await : la mémoire est déjà à jour.
      store.replaceCollection('events_box', {
        'e1': {'title': 'A'},
        'e2': {'title': 'B'},
      });
      store.putDocument('events_box', 'e3', {'title': 'C'});
      store.removeDocument('events_box', 'e1');
      expect(store.readCollection('events_box').keys.toSet(), {'e2', 'e3'});

      final reloaded = await reload();
      expect(reloaded.readCollection('events_box'), {
        'e2': {'title': 'B'},
        'e3': {'title': 'C'},
      });
    });

    test('replaceCollection ne touche pas aux autres collections', () async {
      final store = await openTestDatabase(path: path);
      store.putDocument('articles_box', 'a1', {'title': 'Livre'});
      store.replaceCollection('events_box', {'e1': {}});
      store.replaceCollection('events_box', {'e2': {}});
      final reloaded = await reload();
      expect(reloaded.readCollection('articles_box').keys, ['a1']);
      expect(reloaded.readCollection('events_box').keys, ['e2']);
    });

    test('les lectures sont des copies', () async {
      final store = await openTestDatabase();
      await store.putDocument('c', 'd', {
        'tags': ['a']
      });
      (store.readCollection('c')['d']!['tags'] as List).add('b');
      expect(store.readCollection('c')['d']!['tags'], ['a']);
    });

    test('valeur non stockable : erreur immédiate, mémoire inchangée', () async {
      final store = await openTestDatabase();
      expect(() => store.putDocument('c', 'd', {'x': Object()}), throwsA(isA<JsonUnsupportedObjectError>()));
      expect(store.readCollection('c'), isEmpty);
    });
  });

  group('notifications de changement', () {
    test('chaque écriture annonce sa collection, après la mise à jour de la mémoire', () async {
      final store = await openTestDatabase();
      final seen = <String>[];
      store.changes.listen((c) => seen.add('$c:${store.readCollection(c).length}'));
      store.putDocument('users', 'u1', {'n': 1});
      store.putDocument('events', 'e1', {});
      store.removeDocument('users', 'u1');
      store.removeDocument('users', 'absent'); // rien supprimé : pas d'annonce
      store.replaceCollection('events', {});
      expect(seen, ['users:1', 'events:1', 'users:0', 'events:0']);
    });

    test('readDocument renvoie une copie, ou null', () async {
      final store = await openTestDatabase();
      await store.putDocument('c', 'd', {
        'tags': ['a']
      });
      (store.readDocument('c', 'd')!['tags'] as List).add('b');
      expect(store.readDocument('c', 'd'), {
        'tags': ['a']
      });
      expect(store.readDocument('c', 'absent'), isNull);
    });
  });

  test('deleteLegacyHiveFiles : supprime seulement les anciennes boîtes Hive', () async {
    for (final name in ['events_box.hive', 'events_box.lock', 'offline_queue_box.hive', 'prefs_box.lock']) {
      File(p.join(dir.path, name)).writeAsStringSync('x');
    }
    final kept = [
      File(p.join(dir.path, 'student_card_u1_1.jpg'))..writeAsStringSync('x'),
      File(p.join(dir.path, 'other.hive'))..writeAsStringSync('x'),
    ];

    await LocalDatabase.deleteLegacyHiveFiles(dir: dir);
    await LocalDatabase.deleteLegacyHiveFiles(dir: Directory(p.join(dir.path, 'absent'))); // ne lève pas

    final left = dir.listSync().map((e) => p.basename(e.path)).toSet();
    expect(left, containsAll(kept.map((f) => p.basename(f.path))));
    expect(left.where((n) => n.contains('_box.')), isEmpty);
  });

  group('préférences (kv)', () {
    test('écrire, relire, effacer', () async {
      final store = await openTestDatabase(path: path);
      store.setValue('remembered_email', 'amel@esprit.tn');
      expect(store.getValue('remembered_email'), 'amel@esprit.tn');
      expect((await reload()).getValue('remembered_email'), 'amel@esprit.tn');

      LocalDatabase.instance.setValue('remembered_email', null);
      expect(LocalDatabase.instance.getValue('remembered_email'), isNull);
      expect((await reload()).getValue('remembered_email'), isNull);
    });
  });
}
