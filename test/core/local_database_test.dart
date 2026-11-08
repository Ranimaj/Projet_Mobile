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

    test('schéma : tables, index, version et CHECK sur le type', () async {
      await openTestDatabase(path: path);
      await LocalDatabase.instance.close();
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(path);
      addTearDown(db.close);
      final names = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type IN ('table','index')"))
          .map((r) => r['name'])
          .toSet();
      expect(names, containsAll(['cache_documents', 'offline_queue', 'kv', 'idx_queue_doc', 'idx_queue_time']));
      expect(await db.getVersion(), LocalDatabase.schemaVersion);
      expect(
        () => db.insert('offline_queue', {
          'id': 'x',
          'type': 'upsert',
          'collection': 'c',
          'doc_id': 'd',
          'payload': '{}',
          'queued_at': 0,
        }),
        throwsA(isA<DatabaseException>()),
      );
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

  group('cache', () {
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

  group('file d\'attente', () {
    Future<void> add(LocalDatabase store, String id, DateTime at,
            {Map<String, dynamic>? payload, Iterable<String> replacing = const []}) =>
        store.addQueued(
          id: id,
          type: 'update',
          collection: 'events',
          docId: 'doc-$id',
          payload: payload ?? {'n': id},
          queuedAt: at,
          replacing: replacing,
        );

    test('ordre gardé en mémoire et après rechargement (queued_at puis ajout)', () async {
      final store = await openTestDatabase(path: path);
      final t = DateTime(2026, 11, 8, 10);
      add(store, 'a', t);
      add(store, 'b', t); // même instant : ordre d'ajout
      add(store, 'c', t.add(const Duration(seconds: 1)));
      expect(store.queuedActions.map((r) => r.id), ['a', 'b', 'c']);

      final reloaded = await reload();
      expect(reloaded.queuedActions.map((r) => r.id), ['a', 'b', 'c']);
      expect(reloaded.queuedActions.first.queuedAt, t);
    });

    test('dates du payload : DateTime après rechargement', () async {
      final store = await openTestDatabase(path: path);
      final start = DateTime.utc(2026, 12, 1, 14);
      add(store, 'a', DateTime.now(), payload: {
        'startDate': start,
        'history': [
          {'at': start}
        ],
      });
      final payload = (await reload()).queued('a')!.payload;
      expect(payload['startDate'], start);
      expect(((payload['history'] as List).single as Map)['at'], start);
    });

    test('replacing retire les anciennes actions dans la même transaction', () async {
      final store = await openTestDatabase(path: path);
      add(store, 'a', DateTime(2026));
      add(store, 'b', DateTime(2026), replacing: ['a', 'inconnu']);
      expect(store.queuedActions.map((r) => r.id), ['b']);
      expect((await reload()).queuedActions.map((r) => r.id), ['b']);
    });

    test('updateQueuedPayloads : révision +1, place gardée, persisté', () async {
      final store = await openTestDatabase(path: path);
      add(store, 'a', DateTime(2026));
      add(store, 'b', DateTime(2026));
      expect(store.queued('a')!.revision, 0);
      // Sans await : la modification passe après l'insertion en attente.
      store.updateQueuedPayloads({
        'a': {'n': 'a2'},
        'absent': {'n': 'x'},
      });
      expect(store.queued('a')!.payload, {'n': 'a2'});
      expect(store.queued('a')!.revision, 1);

      final reloaded = await reload();
      expect(reloaded.queuedActions.map((r) => r.id), ['a', 'b']);
      expect(reloaded.queued('a')!.payload, {'n': 'a2'});
    });

    test('removeQueued', () async {
      final store = await openTestDatabase(path: path);
      add(store, 'a', DateTime(2026));
      add(store, 'b', DateTime(2026));
      store.removeQueued(['a']);
      expect(store.queueLength, 1);
      expect((await reload()).queuedActions.map((r) => r.id), ['b']);
    });

    test('écritures en rafale sans await : SQLite finit identique à la mémoire', () async {
      final store = await openTestDatabase(path: path);
      for (var i = 0; i < 50; i++) {
        add(store, 'a$i', DateTime(2026, 1, 1, 0, 0, i));
        if (i.isOdd) store.removeQueued(['a${i - 1}']);
        if (i % 5 == 0) store.updateQueuedPayloads({'a$i': {'n': 'patched'}});
      }
      final memory = store.queuedActions.map((r) => '${r.id}:${r.payload['n']}').toList();
      final reloaded = await reload();
      expect(reloaded.queuedActions.map((r) => '${r.id}:${r.payload['n']}').toList(), memory);
      expect(memory, hasLength(25));
    });
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
