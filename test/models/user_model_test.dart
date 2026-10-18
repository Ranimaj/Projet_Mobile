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
}
