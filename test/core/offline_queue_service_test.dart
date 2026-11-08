import 'dart:async';
import 'dart:io';

import 'package:campusconnect/core/utils/local_database.dart';
import 'package:campusconnect/core/utils/offline_queue_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

import '../helpers/local_db.dart';

class _MockFirestore extends Mock implements FirebaseFirestore {}

// Doublures de test uniquement : il faut pouvoir retarder et observer un
// `set` (le faux Firestore ne le permet pas), donc implémenter ces classes
// marquées @sealed.
// ignore: subtype_of_sealed_class
class _MockCollection extends Mock implements CollectionReference<Map<String, dynamic>> {}

// ignore: subtype_of_sealed_class
class _MockDoc extends Mock implements DocumentReference<Map<String, dynamic>> {}

void main() {
  late Directory dir;
  late String dbPath;
  late OfflineQueueService queue;
  late FakeFirebaseFirestore firestore;

  setUpAll(() => registerFallbackValue(SetOptions(merge: true)));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('queue_test');
    dbPath = p.join(dir.path, 'queue.db');
    await openTestDatabase(path: dbPath);
    queue = OfflineQueueService(appDir: () async => dir);
    firestore = FakeFirebaseFirestore();
  });

  tearDown(() async {
    await closeTestDatabase();
    await dir.delete(recursive: true);
  });

  /// Redémarrage de l'app : seul ce qui a été écrit dans SQLite revient.
  Future<void> restart() async {
    await LocalDatabase.instance.close();
    await openTestDatabase(path: dbPath);
  }

  void enqueueCard(String uid, String file) => queue.enqueue(
        type: QueueActionType.uploadStudentCard,
        collection: 'users',
        docId: uid,
        payload: {
          'uid': uid,
          'file': file,
          'remotePath': 'student_cards/$uid/1.jpg',
          'submittedAt': DateTime(2026, 10, 28, 9).toIso8601String(),
        },
      );

  File localFile(String name) =>
      File('${dir.path}/$name')..writeAsBytesSync([1, 2, 3]);

  test('enqueue keeps a single uploadStudentCard action per uid', () {
    enqueueCard('u1', 'a.jpg');
    enqueueCard('u2', 'b.jpg');
    enqueueCard('u1', 'c.jpg');

    final cards = queue.pendingActions;
    expect(cards, hasLength(2));
    expect(cards.firstWhere((a) => a.docId == 'u1').payload['file'], 'c.jpg');
  });

  test(
      'syncAll uploads the card, writes a pending whole-map and removes the action and local copy',
      () async {
    await firestore.collection('users').doc('u1').set({
      'fullName': 'Amel',
      // (le fake fusionne les maps imbriquées ; Firestore réel les remplace)
      'studentCard': {'status': 'rejected'},
    });
    final local = localFile('student_card_u1.jpg');
    enqueueCard('u1', 'student_card_u1.jpg');
    String? uploaded;

    final result = await queue.syncAll(firestore, upload: (l, r) async {
      uploaded = '$l -> $r';
      return r;
    });

    expect(result.success, 1);
    expect(uploaded, '${local.path} -> student_cards/u1/1.jpg');
    final data = (await firestore.collection('users').doc('u1').get()).data()!;
    expect(data['fullName'], 'Amel');
    final card = data['studentCard'] as Map<String, dynamic>;
    expect(card.keys.toSet(), {'status', 'imagePath', 'submittedAt'});
    expect(card['status'], 'pending');
    expect(card['imagePath'], 'student_cards/u1/1.jpg');
    expect(card['submittedAt'], Timestamp.fromDate(DateTime(2026, 10, 28, 9)));
    expect(queue.pendingCount, 0);
    expect(local.existsSync(), isFalse);
  });

  test('a failing upload keeps the action and the local copy', () async {
    await firestore.collection('users').doc('u1').set({'fullName': 'Amel'});
    final local = localFile('student_card_u1.jpg');
    enqueueCard('u1', 'student_card_u1.jpg');

    final result = await queue.syncAll(firestore,
        upload: (l, r) async => throw Exception('offline'));

    expect(result.failed, 1);
    expect(queue.pendingCount, 1);
    expect(local.existsSync(), isTrue);
    final data = (await firestore.collection('users').doc('u1').get()).data()!;
    expect(data.containsKey('studentCard'), isFalse);
  });

  test('without an upload callback the card action stays queued', () async {
    enqueueCard('u1', 'a.jpg');
    final result = await queue.syncAll(firestore);
    expect(result.failed, 1);
    expect(queue.pendingCount, 1);
  });

  test(
      'an action whose local file is gone is dropped instead of retried forever',
      () async {
    enqueueCard('u1', 'missing.jpg');
    var uploads = 0;

    final result = await queue.syncAll(firestore, upload: (l, r) async {
      uploads++;
      return r;
    });

    expect(uploads, 0);
    expect(result.failed, 0);
    expect(queue.pendingCount, 0);
  });

  test('concurrent syncAll calls replay each action once', () async {
    localFile('student_card_u1.jpg');
    await firestore.collection('users').doc('u1').set({'fullName': 'Amel'});
    enqueueCard('u1', 'student_card_u1.jpg');
    var uploads = 0;
    Future<String> upload(String l, String r) async {
      uploads++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return r;
    }

    final results = await Future.wait([
      queue.syncAll(firestore, upload: upload),
      queue.syncAll(firestore, upload: upload),
    ]);

    expect(uploads, 1);
    expect(results[0], same(results[1]));
    expect(queue.pendingCount, 0);
  });

  test('syncAll keeps card actions of another account', () async {
    localFile('a.jpg');
    localFile('b.jpg');
    await firestore.collection('users').doc('u1').set({'fullName': 'Amel'});
    await firestore.collection('users').doc('u2').set({'fullName': 'Sami'});
    enqueueCard('u1', 'a.jpg');
    enqueueCard('u2', 'b.jpg');
    final uploaded = <String>[];

    await queue.syncAll(firestore, currentUid: 'u2', upload: (l, r) async {
      uploaded.add(r);
      return r;
    });

    expect(uploaded, ['student_cards/u2/1.jpg']);
    expect(queue.pendingActions.single.docId, 'u1');
    expect(File('${dir.path}/a.jpg').existsSync(), isTrue);
  });

  test('removeStudentCardActions purges one account and its files', () async {
    localFile('a.jpg');
    localFile('b.jpg');
    enqueueCard('u1', 'a.jpg');
    enqueueCard('u2', 'b.jpg');

    await queue.removeStudentCardActions('u1');

    expect(queue.pendingActions.single.docId, 'u2');
    expect(File('${dir.path}/a.jpg').existsSync(), isFalse);
    expect(File('${dir.path}/b.jpg').existsSync(), isTrue);
  });

  group('stockage SQLite', () {
    test('dates : DateTime après enqueue puis redémarrage (listes et maps imbriquées)', () async {
      final start = DateTime.utc(2026, 12, 1, 14);
      final end = DateTime.utc(2026, 12, 1, 16);
      queue.enqueue(
        type: QueueActionType.create,
        collection: 'events',
        docId: 'e1',
        payload: {
          'title': 'Forum',
          'startDate': Timestamp.fromDate(start), // converti en DateTime
          'endDate': end,
          'slots': [
            {'at': Timestamp.fromDate(start)},
            end,
          ],
          'meta': {
            'nested': {'createdAt': start}
          },
        },
      );

      await restart();

      final payload = OfflineQueueService().pendingActions.single.payload;
      expect(payload['title'], 'Forum');
      expect(payload['startDate'], isA<DateTime>());
      expect((payload['startDate'] as DateTime).isAtSameMomentAs(start), isTrue);
      expect(payload['endDate'], end);
      final slots = payload['slots'] as List;
      expect((slots[0] as Map)['at'], start);
      expect(slots[1], end);
      expect(((payload['meta'] as Map)['nested'] as Map)['createdAt'], start);
    });

    test('le rejeu envoie des DateTime (pas des String) et Firestore stocke des timestamps', () async {
      final start = DateTime.utc(2026, 12, 1, 14);
      queue.enqueue(
        type: QueueActionType.create,
        collection: 'events',
        docId: 'e1',
        payload: {
          'startDate': Timestamp.fromDate(start),
          'history': [
            {'at': start}
          ],
        },
      );
      await restart();

      final fs = _MockFirestore();
      final col = _MockCollection();
      final doc = _MockDoc();
      when(() => fs.collection('events')).thenReturn(col);
      when(() => col.doc('e1')).thenReturn(doc);
      when(() => doc.set(any(), any())).thenAnswer((_) async {});

      final result = await OfflineQueueService().syncAll(fs);

      expect(result.success, 1);
      final sent = verify(() => doc.set(captureAny(), any())).captured.single as Map<String, dynamic>;
      expect(sent['startDate'], isA<DateTime>());
      expect(sent['startDate'], isNot(isA<String>()));
      expect(((sent['history'] as List).single as Map)['at'], isA<DateTime>());

      // Même chose de bout en bout avec le faux Firestore : un vrai timestamp.
      queue.enqueue(
        type: QueueActionType.create,
        collection: 'events',
        docId: 'e2',
        payload: {'startDate': Timestamp.fromDate(start)},
      );
      await restart();
      await OfflineQueueService().syncAll(firestore);
      final stored = (await firestore.collection('events').doc('e2').get()).data()!;
      expect(stored['startDate'], isA<Timestamp>());
      expect((stored['startDate'] as Timestamp).toDate().isAtSameMomentAs(start), isTrue);
    });

    test('ordre : rejoué dans l\'ordre chronologique, gardé après redémarrage', () async {
      queue.enqueue(type: QueueActionType.create, collection: 'events', docId: 'e1', payload: {'v': 1});
      queue.enqueue(type: QueueActionType.update, collection: 'events', docId: 'e1', payload: {'v': 2});
      queue.enqueue(type: QueueActionType.update, collection: 'events', docId: 'e1', payload: {'v': 3});
      queue.enqueue(type: QueueActionType.delete, collection: 'events', docId: 'e1', payload: const {});
      await restart();
      expect(OfflineQueueService().pendingActions.map((a) => a.type.name),
          ['create', 'update', 'update', 'delete']);

      final fs = _MockFirestore();
      final col = _MockCollection();
      final doc = _MockDoc();
      final calls = <String>[];
      when(() => fs.collection('events')).thenReturn(col);
      when(() => col.doc('e1')).thenReturn(doc);
      when(() => doc.set(any(), any())).thenAnswer((i) async {
        calls.add('set ${(i.positionalArguments.first as Map)['v']}');
      });
      when(() => doc.delete()).thenAnswer((_) async => calls.add('delete'));

      await OfflineQueueService().syncAll(fs);

      expect(calls, ['set 1', 'set 2', 'set 3', 'delete']);
      expect(queue.pendingCount, 0);
    });

    test('patchPending pendant l\'envoi réseau : la version patchée est renvoyée avant le retrait', () async {
      queue.enqueue(
        type: QueueActionType.create,
        collection: 'articles',
        docId: 'a1',
        payload: {
          'title': 'Vélo',
          'imageUrls': ['/data/photo.jpg'],
        },
      );
      final fs = _MockFirestore();
      final col = _MockCollection();
      final doc = _MockDoc();
      final firstSend = Completer<void>();
      final sent = <Map<String, dynamic>>[];
      when(() => fs.collection('articles')).thenReturn(col);
      when(() => col.doc('a1')).thenReturn(doc);
      when(() => doc.set(any(), any())).thenAnswer((i) {
        sent.add(Map<String, dynamic>.from(i.positionalArguments.first as Map));
        return sent.length == 1 ? firstSend.future : Future<void>.value();
      });

      final sync = queue.syncAll(fs);
      await Future<void>.delayed(Duration.zero);
      expect(sent, hasLength(1), reason: 'premier envoi en cours');

      await queue.patchPending('articles', 'a1', {
        'imageUrls': ['https://cdn/photo.jpg']
      });
      firstSend.complete();
      final result = await sync;

      expect(result.success, 1);
      expect(sent.map((m) => m['imageUrls']), [
        ['/data/photo.jpg'],
        ['https://cdn/photo.jpg'],
      ]);
      expect(queue.pendingCount, 0);
      await restart();
      expect(OfflineQueueService().pendingCount, 0);
    });

    test('patchPending sur une écriture SQLite encore en attente : persisté après redémarrage', () async {
      queue.enqueue(
        type: QueueActionType.create,
        collection: 'articles',
        docId: 'a1',
        payload: {
          'title': 'Vélo',
          'imageUrls': ['/data/photo.jpg'],
        },
      );
      // Aucun await entre les deux : l'insertion n'est pas encore dans SQLite.
      final patched = queue.patchPending('articles', 'a1', {
        'imageUrls': ['https://cdn/photo.jpg']
      });
      expect(queue.pendingActions.single.payload['imageUrls'], ['https://cdn/photo.jpg']);
      await patched;

      await restart();
      final payload = OfflineQueueService().pendingActions.single.payload;
      expect(payload['imageUrls'], ['https://cdn/photo.jpg']);
      expect(payload['title'], 'Vélo');
    });

    test('patchPending ne touche que les create / update du document visé', () async {
      queue.enqueue(type: QueueActionType.create, collection: 'articles', docId: 'a1', payload: {'n': 1});
      queue.enqueue(type: QueueActionType.delete, collection: 'articles', docId: 'a1', payload: const {});
      queue.enqueue(type: QueueActionType.update, collection: 'articles', docId: 'a2', payload: {'n': 2});
      queue.enqueue(type: QueueActionType.update, collection: 'annonces', docId: 'a1', payload: {'n': 3});

      await queue.patchPending('articles', 'a1', {'x': true});

      final payloads = queue.pendingActions.map((a) => a.payload).toList();
      expect(payloads, [
        {'n': 1, 'x': true},
        <String, dynamic>{},
        {'n': 2},
        {'n': 3},
      ]);
    });

    test('toutes les instances partagent la même file', () {
      final other = OfflineQueueService();
      queue.enqueue(type: QueueActionType.update, collection: 'events', docId: 'e1', payload: {'v': 1});
      expect(other.pendingCount, 1);
      expect(other.pendingActions.single.docId, 'e1');
    });

    test('carte : le remplacement est aussi persisté', () async {
      enqueueCard('u1', 'a.jpg');
      enqueueCard('u1', 'b.jpg');
      await restart();
      final cards = OfflineQueueService().pendingActions;
      expect(cards, hasLength(1));
      expect(cards.single.payload['file'], 'b.jpg');
    });
  });
}
