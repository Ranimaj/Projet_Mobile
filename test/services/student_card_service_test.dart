import 'dart:io';

import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/services/local_store.dart';
import 'package:campusconnect/services/storage_service.dart';
import 'package:campusconnect/services/student_card_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/local_db.dart';

void main() {
  late Directory dir;
  late LocalStore store;
  late StorageService storage;
  late StudentCardService service;
  late File photo;
  final now = DateTime(2026, 10, 28, 9);

  Map<String, dynamic> stored() => store.get('users', 'u1')!;
  String pathFor(DateTime at) =>
      p.join(dir.path, 'student_cards', 'u1', '${at.millisecondsSinceEpoch}.jpg');

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('card_test');
    await openTestDatabase();
    store = LocalStore();
    // Pas de compression dans les tests : le fichier est copié tel quel.
    storage = StorageService(appDir: () async => dir, compress: (file, _, __) async => file);
    service = StudentCardService(storage: storage, store: store);
    photo = File(p.join(dir.path, 'pick.jpg'))..writeAsBytesSync([9, 9]);
    await store.set('users', 'u1', {
      'fullName': 'Amel',
      'studentCard': {'status': 'rejected', 'rejectReason': 'Photo floue'},
    });
  });

  tearDown(() async {
    await closeTestDatabase();
    await dir.delete(recursive: true);
  });

  test('copies the photo into the app folder and writes a pending whole-map card', () async {
    final card = await service.submit(uid: 'u1', photo: photo, now: () => now);

    final path = pathFor(now);
    expect(card.status, StudentCardStatus.pending);
    expect(card.imagePath, path);
    expect(File(path).readAsBytesSync(), [9, 9]);
    final data = stored();
    expect(data['fullName'], 'Amel');
    final written = data['studentCard'] as Map<String, dynamic>;
    // Remplacement complet : l'ancien motif de refus disparaît.
    expect(written.keys.toSet(), {'status', 'imagePath', 'submittedAt'});
    expect(written['status'], 'pending');
    expect(written['imagePath'], path);
    expect(parseDate(written['submittedAt']), now);
  });

  test('the stored card reads back as an AppUser', () async {
    await service.submit(uid: 'u1', photo: photo, now: () => now);
    final user = AppUser.fromMap('u1', stored());
    expect(user.studentCard.status, StudentCardStatus.pending);
    expect(user.studentCard.imagePath, pathFor(now));
    expect(user.studentCard.submittedAt, now);
    expect(user.studentCard.rejectReason, isNull);
  });

  test('a copy failure writes nothing', () async {
    final missing = File(p.join(dir.path, 'absent.jpg'));

    await expectLater(service.submit(uid: 'u1', photo: missing, now: () => now), throwsA(anything));

    final card = stored()['studentCard'] as Map;
    expect(card['status'], 'rejected');
    expect(card['rejectReason'], 'Photo floue');
  });

  test('an unknown account fails and creates no profile', () async {
    await expectLater(service.submit(uid: 'ghost', photo: photo, now: () => now),
        throwsA(isA<DocumentNotFound>()));
    expect(store.exists('users', 'ghost'), isFalse);
  });

  test('a resubmission replaces the previous photo file', () async {
    await service.submit(uid: 'u1', photo: photo, now: () => now);
    final first = pathFor(now);
    final second = File(p.join(dir.path, 'pick2.jpg'))..writeAsBytesSync([7]);
    final later = now.add(const Duration(minutes: 5));

    final card = await service.submit(uid: 'u1', photo: second, now: () => later);

    expect(card.imagePath, pathFor(later));
    expect(File(pathFor(later)).readAsBytesSync(), [7]);
    expect(File(first).existsSync(), isFalse);
    final copies = Directory(p.join(dir.path, 'student_cards', 'u1'))
        .listSync()
        .map((e) => p.basename(e.path));
    expect(copies, [p.basename(pathFor(later))]);
    expect((stored()['studentCard'] as Map)['imagePath'], pathFor(later));
  });

  test('a previous image that is not a local file is left alone', () async {
    await store.update('users', 'u1', {
      'studentCard': {'status': 'rejected', 'imagePath': 'asset:assets/demo/card.jpg'},
    });

    final card = await service.submit(uid: 'u1', photo: photo, now: () => now);

    expect(card.imagePath, pathFor(now));
    expect(File(pathFor(now)).existsSync(), isTrue);
  });
}
