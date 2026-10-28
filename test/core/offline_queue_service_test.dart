import 'dart:io';

import 'package:campusconnect/core/constants/app_constants.dart';
import 'package:campusconnect/core/utils/offline_queue_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory dir;
  late OfflineQueueService queue;
  late FakeFirebaseFirestore firestore;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('queue_test');
    Hive.init(dir.path);
    await Hive.openBox(AppConstants.hiveOfflineQueueBox);
    queue = OfflineQueueService(appDir: () async => dir);
    firestore = FakeFirebaseFirestore();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

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
}
