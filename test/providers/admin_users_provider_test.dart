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

  testWidgets('filters by role, card status and query (case-insensitive)', (t) async {
    final p = build(users, debounce: const Duration(milliseconds: 400));
    await t.pump();
    p.setRoleFilter(UserRole.recruiter);
    expect(p.filtered.map((u) => u.id), ['r1']);
    p.setRoleFilter(null);
    p.setCardFilter(StudentCardStatus.pending);
    expect(p.filtered.map((u) => u.id), ['s1']);
    p.setCardFilter(null);
    p.setQuery('SAMI');
    await t.pump(const Duration(milliseconds: 401));
    expect(p.query, 'SAMI');
    expect(p.filtered.map((u) => u.id), ['s2']);
    p.setQuery('s1@esprit');
    await t.pump(const Duration(milliseconds: 401));
    expect(p.filtered.map((u) => u.id), ['s1']);
    p.dispose();
  });

  testWidgets('setQuery is debounced: only the last value applies, after 400 ms', (t) async {
    final p = build(users);
    await t.pump();
    p.setQuery('a');
    p.setQuery('amel');
    await t.pump(const Duration(milliseconds: 399));
    expect(p.query, '');
    await t.pump(const Duration(milliseconds: 2));
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

  test('canDisable: never self, never the last enabled admin', () async {
    final p = build(users);
    await Future<void>.delayed(Duration.zero);
    expect(p.canDisable(users.first), isFalse);
    expect(p.canDisable(users[1]), isTrue);
    expect(await p.setDisabled(users.first, true), isFalse);
    verifyNever(() => service.setDisabled(any(), any()));
    p.dispose();
  });

  test('a second admin can be disabled; then the first cannot demote themself', () async {
    final b = _u('a2', 'Admin Deux', role: UserRole.admin);
    final two = [...users, b];
    when(() => service.setDisabled('a2', true)).thenAnswer((_) async {});
    final p = build(two);
    await Future<void>.delayed(Duration.zero);
    expect(p.canDisable(b), isTrue);
    expect(await p.setDisabled(b, true), isTrue);
    verify(() => service.setDisabled('a2', true)).called(1);
    // snapshot after the write: B is now disabled
    stream.add([
      ...users,
      AppUser(
          id: 'a2',
          fullName: 'Admin Deux',
          email: 'a2@esprit.tn',
          role: UserRole.admin,
          disabled: true,
          createdAt: DateTime(2026, 1, 1)),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(p.adminCount, 1);
    expect(p.canChangeRole(users.first, UserRole.student), isFalse);
    expect(p.canDisable(users.first), isFalse);
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
