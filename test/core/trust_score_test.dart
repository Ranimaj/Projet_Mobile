import 'package:campusconnect/core/utils/trust_score.dart';
import 'package:campusconnect/models/user_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 11, 9);
  AppUser user({
    DateTime? createdAt,
    bool card = false,
    bool phone = false,
    bool twoFactor = false,
    double ratingAverage = 0,
    int ratingCount = 0,
    int reportCount = 0,
    bool disabled = false,
  }) =>
      AppUser(
        id: 'u',
        fullName: 'Amel Ben Salah',
        email: 'amel@esprit.tn',
        createdAt: createdAt ?? now,
        isVerifiedStudent: card,
        isPhoneVerified: phone,
        twoFactorEnabled: twoFactor,
        ratingAverage: ratingAverage,
        ratingCount: ratingCount,
        reportCount: reportCount,
        disabled: disabled,
      );

  test('a brand-new unverified account is Nouveau with 0 points', () {
    final t = TrustScore.of(user(), now: now);
    expect(t.score, 0);
    expect(t.level, TrustLevel.nouveau);
    expect(t.pointsToNextLevel, 30);
  });

  test('verifications, age, sales and ratings add up to 100 (Or)', () {
    final t = TrustScore.of(
      user(
        createdAt: DateTime(2025, 1, 1),
        card: true,
        phone: true,
        twoFactor: true,
        ratingAverage: 5,
        ratingCount: 8,
      ),
      completedSales: 9,
      now: now,
    );
    expect(t.score, 100);
    expect(t.level, TrustLevel.or);
    expect(t.pointsToNextLevel, isNull);
    expect(t.factors.every((f) => f.complete), isTrue);
  });

  test('a verified student card alone reaches Bronze only with some age', () {
    expect(TrustScore.of(user(card: true), now: now).level, TrustLevel.nouveau); // 25
    final t = TrustScore.of(user(card: true, createdAt: DateTime(2026, 6, 1)), now: now); // 25 + 5
    expect(t.score, 30);
    expect(t.level, TrustLevel.bronze);
  });

  test('few ratings weigh less than many', () {
    final one = TrustScore.of(user(ratingAverage: 5, ratingCount: 1), now: now);
    final five = TrustScore.of(user(ratingAverage: 5, ratingCount: 5), now: now);
    expect(one.score, 4);
    expect(five.score, 20);
  });

  test('sales are capped at 15 points', () {
    expect(TrustScore.of(user(), completedSales: 2, now: now).score, 6);
    expect(TrustScore.of(user(), completedSales: 40, now: now).score, 15);
  });

  test('each confirmed report removes 15 points, never below 0', () {
    final base = user(card: true, phone: true, twoFactor: true); // 50
    expect(TrustScore.of(base, now: now).level, TrustLevel.bronze);
    final reported = TrustScore.of(
        user(card: true, phone: true, twoFactor: true, reportCount: 2), now: now);
    expect(reported.score, 20);
    expect(reported.penalty, 30);
    expect(reported.level, TrustLevel.nouveau);
    expect(TrustScore.of(user(reportCount: 5), now: now).score, 0);
  });

  test('a disabled account has no trust', () {
    expect(TrustScore.of(user(card: true, phone: true, disabled: true), now: now).score, 0);
  });

  test('reportCount round-trips through Firestore maps', () {
    final u = user(reportCount: 3);
    expect(AppUser.fromMap('u', u.toMap()).reportCount, 3);
    expect(AppUser.fromMap('u', const {'fullName': 'x'}).reportCount, 0);
  });
}
