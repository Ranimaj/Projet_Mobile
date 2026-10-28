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
    queue = OfflineQueueService();
    firestore = FakeFirebaseFirestore();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  void enqueueCard(String uid, String local) => queue.enqueue(
        type: QueueActionType.uploadStudentCard,
        collection: 'users',
        docId: uid,
        payload: {'localPath': local, 'remotePath': 'student_cards/$uid/1.jpg'},
      );

  test('enqueue keeps a single uploadStudentCard action per uid', () {
    enqueueCard('u1', '/a.jpg');
    enqueueCard('u2', '/b.jpg');
    enqueueCard('u1', '/c.jpg');

    final cards = queue.pendingActions;
    expect(cards, hasLength(2));
    expect(cards.firstWhere((a) => a.docId == 'u1').payload['localPath'], '/c.jpg');
  });

  test('syncAll uploads the card, writes a pending whole-map and removes the action and local copy',
      () async {
    await firestore.collection('users').doc('u1').set({
      'fullName': 'Amel',
      // (le fake fusionne les maps imbriquées ; Firestore réel les remplace)
      'studentCard': {'status': 'rejected'},
    });
    final local = File('${dir.path}/student_card_u1.jpg')..writeAsBytesSync([1, 2, 3]);
    enqueueCard('u1', local.path);
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
    expect(card['submittedAt'], isA<Timestamp>());
    expect(queue.pendingCount, 0);
    expect(local.existsSync(), isFalse);
  });

  test('a failing upload keeps the action and the local copy', () async {
    await firestore.collection('users').doc('u1').set({'fullName': 'Amel'});
    final local = File('${dir.path}/student_card_u1.jpg')..writeAsBytesSync([1]);
    enqueueCard('u1', local.path);

    final result = await queue.syncAll(firestore, upload: (l, r) async => throw Exception('offline'));

    expect(result.failed, 1);
    expect(queue.pendingCount, 1);
    expect(local.existsSync(), isTrue);
    final data = (await firestore.collection('users').doc('u1').get()).data()!;
    expect(data.containsKey('studentCard'), isFalse);
  });

  test('without an upload callback the card action stays queued', () async {
    enqueueCard('u1', '/a.jpg');
    final result = await queue.syncAll(firestore);
    expect(result.failed, 1);
    expect(queue.pendingCount, 1);
  });
}
