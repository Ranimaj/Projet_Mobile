import 'dart:async';
import 'dart:io';

import 'package:campusconnect/core/constants/app_constants.dart';
import 'package:campusconnect/core/utils/offline_queue_service.dart';
import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/services/student_card_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

void main() {
  late Directory dir;
  late OfflineQueueService queue;
  late FakeFirebaseFirestore firestore;
  late MockStorageService storage;
  late StudentCardService service;
  late File photo;
  final now = DateTime(2026, 10, 28, 9);

  setUpAll(() => registerFallbackValue(File('x')));

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('card_test');
    Hive.init(dir.path);
    await Hive.openBox(AppConstants.hiveOfflineQueueBox);
    queue = OfflineQueueService(appDir: () async => dir);
    firestore = FakeFirebaseFirestore();
    storage = MockStorageService();
    service = StudentCardService(
      storage: storage,
      firestore: firestore,
      queue: queue,
      appDir: () => dir,
    );
    photo = File('${dir.path}/pick.jpg')..writeAsBytesSync([9, 9]);
    // Le fake fusionne les maps imbriquées à l'update (Firestore réel les
    // remplace) : on part donc d'une carte sans motif pour juger les clés.
    await firestore.collection('users').doc('u1').set({
      'fullName': 'Amel',
      'studentCard': {'status': 'rejected'},
    });
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  test('online: uploads then writes a pending whole-map with the storage path', () async {
    final path = 'student_cards/u1/${now.millisecondsSinceEpoch}.jpg';
    when(() => storage.uploadFile(any(), remotePath: any(named: 'remotePath')))
        .thenAnswer((i) async => i.namedArguments[#remotePath] as String);

    final card = await service.submit(uid: 'u1', photo: photo, isOnline: true, now: () => now);

    verify(() => storage.uploadFile(photo, remotePath: path)).called(1);
    expect(card.status, StudentCardStatus.pending);
    expect(card.imagePath, path);
    final data = (await firestore.collection('users').doc('u1').get()).data()!;
    expect(data['fullName'], 'Amel');
    final written = data['studentCard'] as Map<String, dynamic>;
    expect(written.keys.toSet(), {'status', 'imagePath', 'submittedAt'});
    expect(written['status'], 'pending');
    expect(written['imagePath'], path);
    expect(queue.pendingCount, 0);
  });

  test('online: an upload failure writes nothing', () async {
    when(() => storage.uploadFile(any(), remotePath: any(named: 'remotePath')))
        .thenThrow(Exception('boom'));

    await expectLater(
        service.submit(uid: 'u1', photo: photo, isOnline: true, now: () => now), throwsException);

    final data = (await firestore.collection('users').doc('u1').get()).data()!;
    expect((data['studentCard'] as Map)['status'], 'rejected');
  });

  group('online fallback to the queue', () {
    late StudentCardService quick;

    setUp(() {
      quick = StudentCardService(
        storage: storage,
        firestore: firestore,
        queue: queue,
        appDir: () => dir,
        onlineTimeout: const Duration(milliseconds: 50),
      );
    });

    Future<void> expectQueued(StudentCard card) async {
      expect(card.status, StudentCardStatus.pending);
      expect(card.imagePath, isNull);
      expect(queue.pendingActions.single.type, QueueActionType.uploadStudentCard);
      final data = (await firestore.collection('users').doc('u1').get()).data()!;
      expect((data['studentCard'] as Map)['status'], 'rejected');
    }

    test('an upload that never completes is queued once the timeout expires', () async {
      when(() => storage.uploadFile(any(), remotePath: any(named: 'remotePath')))
          .thenAnswer((_) => Completer<String>().future);

      final card = await quick.submit(uid: 'u1', photo: photo, isOnline: true, now: () => now);

      await expectQueued(card);
    });

    test('a late upload after the timeout writes nothing', () async {
      final upload = Completer<String>();
      when(() => storage.uploadFile(any(), remotePath: any(named: 'remotePath')))
          .thenAnswer((_) => upload.future);

      final card = await quick.submit(uid: 'u1', photo: photo, isOnline: true, now: () => now);
      upload.complete('student_cards/u1/late.jpg');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await expectQueued(card);
    });

    test('a SocketException is queued', () async {
      when(() => storage.uploadFile(any(), remotePath: any(named: 'remotePath')))
          .thenThrow(const SocketException('no route'));
      await expectQueued(
          await quick.submit(uid: 'u1', photo: photo, isOnline: true, now: () => now));
    });

    test('a Firebase network error is queued', () async {
      when(() => storage.uploadFile(any(), remotePath: any(named: 'remotePath')))
          .thenThrow(FirebaseException(plugin: 'firebase_storage', code: 'retry-limit-exceeded'));
      await expectQueued(
          await quick.submit(uid: 'u1', photo: photo, isOnline: true, now: () => now));
    });

    test('a refusal is not queued', () async {
      when(() => storage.uploadFile(any(), remotePath: any(named: 'remotePath')))
          .thenThrow(FirebaseException(plugin: 'firebase_storage', code: 'unauthorized'));
      await expectLater(
          quick.submit(uid: 'u1', photo: photo, isOnline: true, now: () => now),
          throwsA(isA<FirebaseException>()));
      expect(queue.pendingCount, 0);
    });
  });

  test('offline: copies the file and enqueues one uploadStudentCard, no remote write', () async {
    final card = await service.submit(uid: 'u1', photo: photo, isOnline: false, now: () => now);

    expect(card.status, StudentCardStatus.pending);
    expect(card.imagePath, isNull);
    final actions = queue.pendingActions;
    expect(actions, hasLength(1));
    final a = actions.single;
    expect(a.type, QueueActionType.uploadStudentCard);
    expect(a.collection, 'users');
    expect(a.docId, 'u1');
    expect(a.payload['uid'], 'u1');
    expect(a.payload['file'], 'student_card_u1_${now.millisecondsSinceEpoch}.jpg');
    expect(a.payload['submittedAt'], now.toIso8601String());
    expect(a.payload['remotePath'], 'student_cards/u1/${now.millisecondsSinceEpoch}.jpg');
    expect(File('${dir.path}/${a.payload['file']}').readAsBytesSync(), [9, 9]);
    verifyNever(() => storage.uploadFile(any(), remotePath: any(named: 'remotePath')));
    final data = (await firestore.collection('users').doc('u1').get()).data()!;
    expect((data['studentCard'] as Map)['status'], 'rejected');
    expect(service.hasQueuedSubmission('u1'), isTrue);
    expect(service.hasQueuedSubmission('u2'), isFalse);
  });

  test('a second offline submit replaces the queued action with the newest file', () async {
    await service.submit(uid: 'u1', photo: photo, isOnline: false, now: () => now);
    final second = File('${dir.path}/pick2.jpg')..writeAsBytesSync([7]);
    final later = now.add(const Duration(minutes: 5));

    await service.submit(uid: 'u1', photo: second, isOnline: false, now: () => later);

    final actions = queue.pendingActions
        .where((a) => a.type == QueueActionType.uploadStudentCard && a.docId == 'u1');
    expect(actions, hasLength(1));
    expect(actions.single.payload['remotePath'],
        'student_cards/u1/${later.millisecondsSinceEpoch}.jpg');
    final newest = File('${dir.path}/${actions.single.payload['file']}');
    expect(newest.readAsBytesSync(), [7]);
    final copies = dir
        .listSync()
        .map((e) => e.path.split('/').last)
        .where((n) => n.startsWith('student_card_'))
        .toList();
    expect(copies, [newest.path.split('/').last]);
  });

  test('two offline submits keep distinct files until the first is superseded', () async {
    await service.submit(uid: 'u1', photo: photo, isOnline: false, now: () => now);
    final first = queue.pendingActions.single.payload['file'];
    final second = File('${dir.path}/pick2.jpg')..writeAsBytesSync([7]);
    await service.submit(
        uid: 'u1', photo: second, isOnline: false, now: () => now.add(const Duration(seconds: 1)));

    final newest = queue.pendingActions.single.payload['file'];
    expect(newest, isNot(first));
    expect(File('${dir.path}/$first').existsSync(), isFalse);
    expect(File('${dir.path}/$newest').existsSync(), isTrue);
  });

  test('discardQueued drops the pending card and its file', () async {
    await service.submit(uid: 'u1', photo: photo, isOnline: false, now: () => now);
    final file = queue.pendingActions.single.payload['file'];

    await service.discardQueued('u1');

    expect(service.hasQueuedSubmission('u1'), isFalse);
    expect(File('${dir.path}/$file').existsSync(), isFalse);
  });

  test('queued replay then writes a pending card', () async {
    await service.submit(uid: 'u1', photo: photo, isOnline: false, now: () => now);

    await queue.syncAll(firestore, upload: (l, r) async => r);

    final data = (await firestore.collection('users').doc('u1').get()).data()!;
    final written = data['studentCard'] as Map<String, dynamic>;
    expect(written.keys.toSet(), {'status', 'imagePath', 'submittedAt'});
    expect(queue.pendingCount, 0);
  });
}
