import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/services/admin_user_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MockStorageService storage;
  late AdminUserService service;
  final submitted = DateTime(2026, 10, 20, 8);
  final now = DateTime(2026, 10, 28, 9);

  setUp(() async {
    db = FakeFirebaseFirestore();
    storage = MockStorageService();
    service = AdminUserService(db, storage: storage);
    await db.collection('users').doc('u1').set({
      'fullName': 'Amel',
      'email': 'amel@esprit.tn',
      'role': 'student',
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      'studentCard': {
        'status': 'pending',
        'imagePath': 'student_cards/u1/card.jpg',
        'submittedAt': Timestamp.fromDate(submitted),
      },
    });
    await db.collection('users').doc('u2').set({
      'fullName': 'Karim',
      'email': 'karim@esprit.tn',
      'role': 'recruiter',
      'createdAt': Timestamp.fromDate(DateTime(2026, 3, 1)),
    });
  });

  test('watchAll emits users, newest first', () async {
    final users = await service.watchAll().first;
    expect(users.map((u) => u.id), ['u2', 'u1']);
    expect(users.last.studentCard.status, StudentCardStatus.pending);
  });

  test('setRole writes the role name', () async {
    await service.setRole('u1', UserRole.admin);
    expect((await db.collection('users').doc('u1').get()).data()!['role'], 'admin');
  });

  test('setDisabled writes the flag', () async {
    await service.setDisabled('u1', true);
    expect((await db.collection('users').doc('u1').get()).data()!['disabled'], true);
  });

  test('approve keeps imagePath/submittedAt and verifies the student', () async {
    await service.reviewCard(uid: 'u1', approve: true, reviewerUid: 'admin-1', now: () => now);
    final data = (await db.collection('users').doc('u1').get()).data()!;
    expect(data['isVerifiedStudent'], true);
    final card = data['studentCard'] as Map<String, dynamic>;
    expect(card['status'], 'verified');
    expect(card['imagePath'], 'student_cards/u1/card.jpg');
    expect((card['submittedAt'] as Timestamp).toDate(), submitted);
    expect(card['reviewedBy'], 'admin-1');
    expect((card['reviewedAt'] as Timestamp).toDate(), now);
    expect(card.containsKey('rejectReason'), isFalse);
  });

  test('reject records the reason and does not verify', () async {
    await service.reviewCard(
        uid: 'u1', approve: false, reason: 'Photo floue', reviewerUid: 'admin-1', now: () => now);
    final data = (await db.collection('users').doc('u1').get()).data()!;
    expect(data['isVerifiedStudent'], false);
    final card = data['studentCard'] as Map<String, dynamic>;
    expect(card['status'], 'rejected');
    expect(card['rejectReason'], 'Photo floue');
    expect(card['reviewedBy'], 'admin-1');
    expect((card['reviewedAt'] as Timestamp).toDate(), now);
    expect(card['imagePath'], 'student_cards/u1/card.jpg');
  });

  test('cardImageUrl delegates to storage', () async {
    when(() => storage.downloadUrl('a/b.jpg')).thenAnswer((_) async => 'https://x/y');
    expect(await service.cardImageUrl('a/b.jpg'), 'https://x/y');
  });
}
