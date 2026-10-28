import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/services/user_stats_service.dart';
import 'package:flutter_test/flutter_test.dart';

AppUser _u(DateTime createdAt,
        {UserRole role = UserRole.student, StudentCardStatus card = StudentCardStatus.none}) =>
    AppUser(
      id: createdAt.toIso8601String() + role.name,
      fullName: 'U',
      email: 'u@esprit.tn',
      role: role,
      createdAt: createdAt,
      studentCard: StudentCard(status: card),
    );

void main() {
  // Window of 7 days ending today (inclusive): 22..28 Oct; previous: 15..21 Oct.
  final now = DateTime(2026, 10, 28, 15, 30);

  test('counts sign-ups inside the window only, today included', () {
    final stats = aggregate([
      _u(DateTime(2026, 10, 28, 0, 1)),
      _u(DateTime(2026, 10, 22, 23, 59)),
      _u(DateTime(2026, 10, 21, 23, 59)), // previous window
      _u(DateTime(2026, 9, 1)),
    ], now: now, days: 7);
    expect(stats.signUps, 2);
  });

  test('changePercent compares with the previous window', () {
    final doubled = aggregate([
      _u(DateTime(2026, 10, 27)),
      _u(DateTime(2026, 10, 28)),
      _u(DateTime(2026, 10, 20)),
    ], now: now, days: 7);
    expect(doubled.changePercent, 100);

    final dropped = aggregate([
      _u(DateTime(2026, 10, 27)),
      _u(DateTime(2026, 10, 20)),
      _u(DateTime(2026, 10, 19)),
      _u(DateTime(2026, 10, 18)),
      _u(DateTime(2026, 10, 17)),
    ], now: now, days: 7);
    expect(dropped.changePercent, -75);
  });

  test('changePercent is null when the previous window is empty', () {
    final stats = aggregate([_u(DateTime(2026, 10, 27))], now: now, days: 7);
    expect(stats.changePercent, isNull);
  });

  test('signUpsPerDay has one point per day, labelled by day of month for 7 days', () {
    final stats = aggregate([
      _u(DateTime(2026, 10, 28)),
      _u(DateTime(2026, 10, 28, 9)),
      _u(DateTime(2026, 10, 24)),
    ], now: now, days: 7);
    expect(stats.signUpsPerDay.map((p) => p.label), ['22', '23', '24', '25', '26', '27', '28']);
    expect(stats.signUpsPerDay.map((p) => p.value), [0, 0, 1, 0, 0, 0, 2]);
  });

  test('longer windows use d/M labels', () {
    final stats = aggregate([], now: now, days: 30);
    expect(stats.signUpsPerDay, hasLength(30));
    expect(stats.signUpsPerDay.first.label, '29/9');
    expect(stats.signUpsPerDay.last.label, '28/10');
  });

  test('byRole and cardsByStatus count every user, whatever the date', () {
    final stats = aggregate([
      _u(DateTime(2020, 1, 1), role: UserRole.admin),
      _u(DateTime(2026, 10, 28), card: StudentCardStatus.pending),
      _u(DateTime(2025, 1, 1), card: StudentCardStatus.verified),
      _u(DateTime(2025, 1, 2), role: UserRole.recruiter, card: StudentCardStatus.rejected),
      _u(DateTime(2025, 1, 3), card: StudentCardStatus.pending),
    ], now: now, days: 7);
    expect(stats.byRole[UserRole.student], 3);
    expect(stats.byRole[UserRole.admin], 1);
    expect(stats.byRole[UserRole.recruiter], 1);
    expect(stats.cardsByStatus[StudentCardStatus.pending], 2);
    expect(stats.cardsByStatus[StudentCardStatus.verified], 1);
    expect(stats.cardsByStatus[StudentCardStatus.rejected], 1);
    expect(stats.cardsByStatus[StudentCardStatus.none], 1);
    expect(stats.pendingCards, 2);
  });
}
