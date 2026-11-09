import 'package:campusconnect/core/utils/auth_failure.dart';
import 'package:campusconnect/core/utils/password_hasher.dart';
import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/services/admin_user_service.dart';
import 'package:campusconnect/services/auth_service.dart';
import 'package:campusconnect/services/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/local_db.dart';
import '../helpers/mocks.dart';

void main() {
  late LocalStore store;
  late MockAuthService auth;
  late AdminUserService service;
  final submitted = DateTime(2026, 10, 20, 8);
  final now = DateTime(2026, 10, 28, 9);

  Map<String, dynamic> user(String id) => store.get('users', id)!;

  setUp(() async {
    await openTestDatabase();
    store = LocalStore();
    auth = MockAuthService();
    service = AdminUserService(store: store, auth: auth);
    await store.set('users', 'u1', {
      'fullName': 'Amel',
      'email': 'amel@esprit.tn',
      'role': 'student',
      'createdAt': DateTime(2026, 1, 1),
      'studentCard': {
        'status': 'pending',
        'imagePath': '/app/student_cards/u1/card.jpg',
        'submittedAt': submitted,
      },
    });
    await store.set('users', 'u2', {
      'fullName': 'Karim',
      'email': 'karim@esprit.tn',
      'role': 'recruiter',
      'createdAt': DateTime(2026, 3, 1),
    });
  });

  tearDown(closeTestDatabase);

  test('watchAll emits users, newest first', () async {
    final users = await service.watchAll().first;
    expect(users.map((u) => u.id), ['u2', 'u1']);
    expect(users.last.studentCard.status, StudentCardStatus.pending);
  });

  test('watchAll keeps legacy users without createdAt, listed last', () async {
    await store.set('users', 'legacy', {
      'fullName': 'Ancien',
      'email': 'ancien@esprit.tn',
      'role': 'student',
    });
    final users = await service.watchAll().first;
    expect(users.map((u) => u.id), ['u2', 'u1', 'legacy']);
  });

  test('watchAll emits again after a change', () async {
    final emitted = service.watchAll().take(2).toList();
    await service.setDisabled('u2', true);
    final lists = await emitted;
    expect(lists.last.firstWhere((u) => u.id == 'u2').disabled, isTrue);
  });

  group('reviewCard conflicts', () {
    test('a matching imagePath is written', () async {
      await service.reviewCard(
          uid: 'u1',
          approve: true,
          reviewerUid: 'admin-1',
          expectedImagePath: '/app/student_cards/u1/card.jpg',
          now: () => now);
      expect((user('u1')['studentCard'] as Map)['status'], 'verified');
    });

    test('a resubmitted card is not written and the conflict surfaces', () async {
      await store.update('users', 'u1', {
        'studentCard': {
          'status': 'pending',
          'imagePath': '/app/student_cards/u1/new.jpg',
          'submittedAt': now,
        },
      });
      await expectLater(
        service.reviewCard(
            uid: 'u1',
            approve: true,
            reviewerUid: 'admin-1',
            expectedImagePath: '/app/student_cards/u1/card.jpg',
            now: () => now),
        throwsA(isA<AdminReviewConflict>()
            .having((e) => e.message, 'message', 'La carte a changé, rouvre-la')),
      );
      final data = user('u1');
      expect((data['studentCard'] as Map)['status'], 'pending');
      expect((data['studentCard'] as Map)['imagePath'], '/app/student_cards/u1/new.jpg');
      expect(data.containsKey('isVerifiedStudent'), isFalse);
    });

    test('an unknown account fails without creating it', () async {
      await expectLater(
        service.reviewCard(
            uid: 'ghost', approve: true, reviewerUid: 'admin-1', expectedImagePath: null),
        throwsA(isA<DocumentNotFound>()),
      );
      expect(store.exists('users', 'ghost'), isFalse);
    });
  });

  test('setRole writes the role name', () async {
    await service.setRole('u1', UserRole.admin);
    expect(user('u1')['role'], 'admin');
  });

  test('setDisabled writes the flag', () async {
    await service.setDisabled('u1', true);
    expect(user('u1')['disabled'], true);
  });

  test('setRole on an unknown account does not create it', () async {
    expect(() => service.setRole('ghost', UserRole.admin), throwsA(isA<DocumentNotFound>()));
    expect(store.exists('users', 'ghost'), isFalse);
  });

  test('approve keeps imagePath/submittedAt and verifies the student', () async {
    await service.reviewCard(
        uid: 'u1',
        approve: true,
        reviewerUid: 'admin-1',
        expectedImagePath: '/app/student_cards/u1/card.jpg',
        now: () => now);
    final data = user('u1');
    expect(data['isVerifiedStudent'], true);
    final card = data['studentCard'] as Map<String, dynamic>;
    expect(card['status'], 'verified');
    expect(card['imagePath'], '/app/student_cards/u1/card.jpg');
    expect(parseDate(card['submittedAt']), submitted);
    expect(card['reviewedBy'], 'admin-1');
    expect(parseDate(card['reviewedAt']), now);
    expect(card.containsKey('rejectReason'), isFalse);
  });

  test('reject records the reason and does not verify', () async {
    await service.reviewCard(
        uid: 'u1',
        approve: false,
        reason: 'Photo floue',
        reviewerUid: 'admin-1',
        expectedImagePath: '/app/student_cards/u1/card.jpg',
        now: () => now);
    final data = user('u1');
    expect(data['isVerifiedStudent'], false);
    final card = data['studentCard'] as Map<String, dynamic>;
    expect(card['status'], 'rejected');
    expect(card['rejectReason'], 'Photo floue');
    expect(card['reviewedBy'], 'admin-1');
    expect(parseDate(card['reviewedAt']), now);
    expect(card['imagePath'], '/app/student_cards/u1/card.jpg');
  });

  test('the reviewed card reads back as an AppUser', () async {
    await service.reviewCard(
        uid: 'u1',
        approve: true,
        reviewerUid: 'admin-1',
        expectedImagePath: '/app/student_cards/u1/card.jpg',
        now: () => now);
    final reread = AppUser.fromMap('u1', user('u1'));
    expect(reread.isVerifiedStudent, isTrue);
    expect(reread.studentCard.reviewedAt, now);
    expect(reread.studentCard.submittedAt, submitted);
  });

  group('resetPassword', () {
    test('delegates to AuthService.resetPasswordByAdmin', () async {
      when(() => auth.resetPasswordByAdmin('u1')).thenAnswer((_) async => 'Campus-abcdef42');
      expect(await service.resetPassword('u1'), 'Campus-abcdef42');
      verify(() => auth.resetPasswordByAdmin('u1')).called(1);
    });

    test('propagates the failure', () async {
      when(() => auth.resetPasswordByAdmin('ghost'))
          .thenThrow(AuthFailure.fromCode('user-not-found'));
      expect(() => service.resetPassword('ghost'), throwsA(isA<AuthFailure>()));
    });

    test('with the real AuthService: the temporary password signs in, the old one no longer', () async {
      final real = AuthService(store: store, hasher: PasswordHasher(iterations: 10));
      final created = await real.registerWithEmail(
          email: 'nour@esprit.tn', password: 'Ancien-Mot1', fullName: 'Nour Trabelsi');
      await real.signOut();
      final admin = AdminUserService(store: store, auth: real);

      final temporary = await admin.resetPassword(created.id);

      expect(temporary, isNot('Ancien-Mot1'));
      await expectLater(
          real.signInWithEmail('nour@esprit.tn', 'Ancien-Mot1'), throwsA(isA<AuthFailure>()));
      final account = await real.signInWithEmail('nour@esprit.tn', temporary);
      expect(account.uid, created.id);
    });
  });
}
