import 'package:campusconnect/core/constants/app_constants.dart';
import 'package:campusconnect/models/user_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final user = AppUser(
    id: 'u1',
    fullName: 'Amel Ben Salah',
    email: 'amel@esprit.tn',
    major: 'GL',
    year: '3ème année',
    isVerifiedStudent: true,
    isPhoneVerified: true,
    phoneNumber: '+21620123456',
    role: UserRole.recruiter,
    twoFactorEnabled: true,
    createdAt: DateTime(2024, 9, 1),
    ratingAverage: 4.5,
    ratingCount: 12,
    skills: const ['Flutter', 'Dart'],
    updatedAt: DateTime(2025, 1, 2),
  );

  test('toMap / fromMap round-trips every field', () {
    final restored = AppUser.fromMap('u1', user.toMap());
    expect(restored.fullName, user.fullName);
    expect(restored.email, user.email);
    expect(restored.major, 'GL');
    expect(restored.year, '3ème année');
    expect(restored.isVerifiedStudent, isTrue);
    expect(restored.isPhoneVerified, isTrue);
    expect(restored.phoneNumber, '+21620123456');
    expect(restored.role, UserRole.recruiter);
    expect(restored.twoFactorEnabled, isTrue);
    expect(restored.createdAt, DateTime(2024, 9, 1));
    expect(restored.updatedAt, DateTime(2025, 1, 2));
    expect(restored.ratingAverage, 4.5);
    expect(restored.ratingCount, 12);
    expect(restored.skills, ['Flutter', 'Dart']);
  });

  test('toEditableMap contains exactly the user-editable fields', () {
    final editable = user.toEditableMap();
    expect(editable.keys.toSet(), AppUser.editableFields);
    expect(editable, isNot(contains('role')));
    expect(editable, isNot(contains('isVerifiedStudent')));
    expect(editable, isNot(contains('email')));
    expect(editable, isNot(contains('phoneNumber')));
    expect(editable, isNot(contains('ratingAverage')));
    expect(editable['fullName'], 'Amel Ben Salah');
    expect(editable['skills'], ['Flutter', 'Dart']);
  });

  test('fromMap tolerates missing fields and ISO date strings', () {
    final minimal = AppUser.fromMap('u2', {
      'fullName': 'X Y',
      'createdAt': '2023-05-06T00:00:00.000',
      'updatedAt': Timestamp.fromDate(DateTime(2024, 1, 1)),
    });
    expect(minimal.email, '');
    expect(minimal.role, UserRole.student);
    expect(minimal.isPhoneVerified, isFalse);
    expect(minimal.phoneNumber, isNull);
    expect(minimal.skills, isEmpty);
    expect(minimal.createdAt, DateTime(2023, 5, 6));
    expect(minimal.updatedAt, DateTime(2024, 1, 1));
  });

  test('unknown role falls back to student', () {
    expect(AppUser.fromMap('u', {'role': 'superuser'}).role, UserRole.student);
  });

  test('initials handle single and multiple names', () {
    expect(user.initials, 'AS');
    expect(user.copyWith(fullName: 'Amel').initials, 'A');
  });

  test('copyWith keeps protected fields and updates the rest', () {
    final copy = user.copyWith(fullName: 'New Name', phoneNumber: '+21699999999', skills: const []);
    expect(copy.fullName, 'New Name');
    expect(copy.phoneNumber, '+21699999999');
    expect(copy.skills, isEmpty);
    expect(copy.role, UserRole.recruiter);
    expect(copy.email, user.email);
    expect(copy.createdAt, user.createdAt);
  });

  group('student card, campus and disabled', () {
    test('fromMap without the new keys gives defaults', () {
      final u = AppUser.fromMap('u3', {'fullName': 'A B', 'email': 'a@b.c'});
      expect(u.campus, AppConstants.defaultCampus);
      expect(u.studentId, isNull);
      expect(u.disabled, isFalse);
      expect(u.studentCard, StudentCard.none);
      expect(u.studentCard.status, StudentCardStatus.none);
    });

    test('toMap writes the defaults a fresh profile needs', () {
      final map = AppUser(
        id: 'u4',
        fullName: 'A B',
        email: 'a@b.c',
        createdAt: DateTime(2024),
      ).toMap();
      expect(map['campus'], 'ESPRIT Ghazela');
      expect(map.containsKey('studentId'), isTrue);
      expect(map['studentId'], isNull);
      expect(map['disabled'], isFalse);
      expect((map['studentCard'] as Map)['status'], 'none');
    });

    test('toMap / fromMap round-trips studentCard, campus and studentId', () {
      final card = StudentCard(
        status: StudentCardStatus.rejected,
        imagePath: 'student_cards/u1/card.jpg',
        submittedAt: DateTime(2025, 2, 1),
        reviewedBy: 'admin1',
        reviewedAt: DateTime(2025, 2, 2),
        rejectReason: 'Illisible',
      );
      final u = user.copyWith(campus: 'ESPRIT Charguia', studentId: '12345', studentCard: card);
      final restored = AppUser.fromMap('u1', u.toMap());
      expect(restored.studentCard, card);
      expect(restored.campus, 'ESPRIT Charguia');
      expect(restored.studentId, '12345');
      expect((u.toMap()['studentCard'] as Map)['status'], 'rejected');
      expect((u.toMap()['studentCard'] as Map)['submittedAt'], isA<Timestamp>());
    });

    test('StudentCard.fromMap tolerates null and unknown status', () {
      expect(StudentCard.fromMap(null), StudentCard.none);
      expect(StudentCard.fromMap(const {}), StudentCard.none);
      expect(StudentCard.fromMap(const {'status': 'bogus'}), StudentCard.none);
    });

    test('toEditableMap contains studentCard, campus, studentId but never disabled', () {
      final editable = user.toEditableMap();
      expect(editable, contains('studentCard'));
      expect(editable, contains('campus'));
      expect(editable, contains('studentId'));
      expect(editable, isNot(contains('disabled')));
      expect(AppUser.editableFields, containsAll(['campus', 'studentId', 'studentCard']));
    });

    test('departments list is exposed', () {
      expect(AppConstants.departments.first, 'Génie Informatique');
      expect(AppConstants.departments.last, 'Autre');
      expect(AppConstants.departments, hasLength(7));
    });
  });
}
