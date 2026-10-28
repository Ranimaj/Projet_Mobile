import 'dart:async';

import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/providers/admin_users_provider.dart';
import 'package:campusconnect/services/admin_user_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockService extends Mock implements AdminUserService {}

AppUser _u(String id, String name,
        {UserRole role = UserRole.student,
        StudentCardStatus card = StudentCardStatus.none}) =>
    AppUser(
      id: id,
      fullName: name,
      email: '$id@esprit.tn',
      role: role,
      createdAt: DateTime(2026, 1, 1),
      studentCard: StudentCard(status: card),
    );

void main() {
  late _MockService service;
  late StreamController<List<AppUser>> stream;

  AdminUsersProvider build(List<AppUser> users, {Duration? debounce}) {
    stream = StreamController<List<AppUser>>();
    when(() => service.watchAll()).thenAnswer((_) => stream.stream);
    final p = AdminUsersProvider(service,
        currentAdminUid: 'a1', debounce: debounce ?? const Duration(milliseconds: 400));
    stream.add(users);
    return p;
  }

  setUpAll(() => registerFallbackValue(UserRole.student));

  setUp(() => service = _MockService());

  final users = [
    _u('a1', 'Admin Un', role: UserRole.admin),
    _u('s1', 'Amel Ben Salah', card: StudentCardStatus.pending),
    _u('s2', 'Sami Trabelsi', card: StudentCardStatus.verified),
    _u('r1', 'Rim Recruteur', role: UserRole.recruiter),
  ];

  test('loading until first snapshot, then users', () async {
    final p = build(users);
    expect(p.isLoading, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(p.isLoading, isFalse);
    expect(p.users, hasLength(4));
    p.dispose();
  });

  test('stream error surfaces a French message', () async {
    final p = build([]);
    stream.addError(Exception('boom'));
    await Future<void>.delayed(Duration.zero);
    expect(p.error, isNotNull);
    expect(p.isLoading, isFalse);
    p.dispose();
  });

  test('filters by role, card status and query (case-insensitive)', () async {
    final p = build(users);
    await Future<void>.delayed(Duration.zero);
    p.setRoleFilter(UserRole.recruiter);
    expect(p.filtered.map((u) => u.id), ['r1']);
    p.setRoleFilter(null);
    p.setCardFilter(StudentCardStatus.pending);
    expect(p.filtered.map((u) => u.id), ['s1']);
    p.setCardFilter(null);
    p.setQuery('SAMI');
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(p.query, 'SAMI');
    expect(p.filtered.map((u) => u.id), ['s2']);
    p.setQuery('s1@esprit');
    await Future<void>.delayed(const Duration(milliseconds: 450));
    expect(p.filtered.map((u) => u.id), ['s1']);
    p.dispose();
  });

  test('setQuery is debounced: only the last value applies, after the delay', () async {
    final p = build(users, debounce: const Duration(milliseconds: 80));
    await Future<void>.delayed(Duration.zero);
    p.setQuery('a');
    p.setQuery('amel');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(p.query, '');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(p.query, 'amel');
    expect(p.filtered.map((u) => u.id), ['s1']);
    p.dispose();
  });

  test('canChangeRole: the last admin cannot demote themself', () async {
    final p = build(users);
    await Future<void>.delayed(Duration.zero);
    expect(p.adminCount, 1);
    final me = users.first;
    expect(p.canChangeRole(me, UserRole.student), isFalse);
    expect(p.canChangeRole(me, UserRole.admin), isTrue);
    expect(p.canChangeRole(users[1], UserRole.admin), isTrue);
    p.dispose();
  });

  test('canChangeRole: another admin can be demoted when two exist', () async {
    final two = [...users, _u('a2', 'Admin Deux', role: UserRole.admin)];
    final p = build(two);
    await Future<void>.delayed(Duration.zero);
    expect(p.adminCount, 2);
    expect(p.canChangeRole(two.first, UserRole.student), isTrue);
    expect(p.canChangeRole(two.last, UserRole.student), isTrue);
    p.dispose();
  });

  test('actions delegate to the service; errors surface', () async {
    final p = build(users);
    await Future<void>.delayed(Duration.zero);
    when(() => service.setRole('s1', UserRole.recruiter)).thenAnswer((_) async {});
    when(() => service.setDisabled('s1', true)).thenThrow(Exception('denied'));
    expect(await p.changeRole(users[1], UserRole.recruiter), isTrue);
    verify(() => service.setRole('s1', UserRole.recruiter)).called(1);
    expect(await p.setDisabled(users[1], true), isFalse);
    expect(p.error, isNotNull);
    p.dispose();
  });

  test('changeRole is refused for the last admin demoting themself', () async {
    final p = build(users);
    await Future<void>.delayed(Duration.zero);
    expect(await p.changeRole(users.first, UserRole.student), isFalse);
    verifyNever(() => service.setRole(any(), any()));
    p.dispose();
  });

  test('reviewCard passes the current admin uid', () async {
    when(() => service.reviewCard(
        uid: any(named: 'uid'),
        approve: any(named: 'approve'),
        reason: any(named: 'reason'),
        reviewerUid: any(named: 'reviewerUid'))).thenAnswer((_) async {});
    final p = build(users);
    await Future<void>.delayed(Duration.zero);
    expect(await p.reviewCard(users[1], approve: false, reason: 'Illisible'), isTrue);
    verify(() => service.reviewCard(
        uid: 's1', approve: false, reason: 'Illisible', reviewerUid: 'a1')).called(1);
    p.dispose();
  });
}
