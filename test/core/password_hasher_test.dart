import 'dart:math';

import 'package:campusconnect/core/utils/password_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final hasher = PasswordHasher(iterations: 10);

  test('the right password verifies, a wrong one does not', () {
    final stored = hasher.hash('secret123');
    expect(PasswordHasher.verify('secret123', stored), isTrue);
    expect(PasswordHasher.verify('secret124', stored), isFalse);
    expect(PasswordHasher.verify('', stored), isFalse);
    expect(PasswordHasher.verify('Secret123', stored), isFalse);
  });

  test('never stores the password itself', () {
    final stored = hasher.hash('secret123');
    expect(stored.toMap().values.join(), isNot(contains('secret123')));
  });

  test('each hash gets its own salt', () {
    final a = hasher.hash('secret123');
    final b = hasher.hash('secret123');
    expect(a.salt, isNot(b.salt));
    expect(a.hash, isNot(b.hash));
    expect(PasswordHasher.verify('secret123', a), isTrue);
    expect(PasswordHasher.verify('secret123', b), isTrue);
  });

  test('is deterministic for a given salt (seeded random)', () {
    final a = PasswordHasher(iterations: 10, random: Random(1)).hash('secret123');
    final b = PasswordHasher(iterations: 10, random: Random(1)).hash('secret123');
    expect(a.salt, b.salt);
    expect(a.hash, b.hash);
  });

  test('the iteration count is stored and used to verify', () {
    final stored = PasswordHasher(iterations: 3).hash('secret123');
    expect(stored.iterations, 3);
    expect(PasswordHasher.verify('secret123', stored), isTrue);

    final tampered = PasswordHash(salt: stored.salt, hash: stored.hash, iterations: 4);
    expect(PasswordHasher.verify('secret123', tampered), isFalse);
  });

  test('the default is the slow setting', () {
    expect(PasswordHasher().iterations, PasswordHasher.defaultIterations);
    expect(PasswordHasher.defaultIterations, greaterThanOrEqualTo(10000));
  });

  test('handles non-ASCII passwords', () {
    final stored = hasher.hash('motdepassé€1');
    expect(PasswordHasher.verify('motdepassé€1', stored), isTrue);
    expect(PasswordHasher.verify('motdepasse€1', stored), isFalse);
  });

  test('matches the PBKDF2-HMAC-SHA256 reference vectors', () {
    // Valeurs de référence (Python hashlib.pbkdf2_hmac, 32 octets).
    const salt = 'c2FsdA=='; // "salt"
    expect(
      PasswordHasher.verify(
        'passwd',
        const PasswordHash(salt: salt, hash: 'VawEblbjCJ/sFpHCJUS2BflBhSFt3gRl5oudV8INrLw=', iterations: 1),
      ),
      isTrue,
    );
    expect(
      PasswordHasher.verify(
        'password',
        const PasswordHash(salt: salt, hash: 'rk0Mla9rRtMtCt/5KPBt0CowP47zwlHf1uLYWpVHTEM=', iterations: 2),
      ),
      isTrue,
    );
  });

  group('PasswordHash map', () {
    test('round-trips through toMap / fromMap', () {
      final stored = hasher.hash('secret123');
      final back = PasswordHash.fromMap(stored.toMap())!;
      expect(back.salt, stored.salt);
      expect(back.hash, stored.hash);
      expect(back.iterations, stored.iterations);
      expect(PasswordHasher.verify('secret123', back), isTrue);
    });

    test('rejects a missing or malformed map', () {
      expect(PasswordHash.fromMap(null), isNull);
      expect(PasswordHash.fromMap({'salt': 'abc'}), isNull);
      expect(PasswordHash.fromMap({'salt': 1, 'hash': 'x'}), isNull);
    });

    test('an old record without iterations falls back to the default', () {
      final back = PasswordHash.fromMap({'salt': 'c2FsdA==', 'hash': 'eA=='})!;
      expect(back.iterations, PasswordHasher.defaultIterations);
    });
  });

  test('une empreinte illisible ne correspond à aucun mot de passe', () {
    const corrupt = PasswordHash(salt: 'pas du base64 !', hash: '%%%', iterations: 1);
    expect(PasswordHasher.verify('Campus2026!', corrupt), isFalse);
    const noIterations = PasswordHash(salt: 'AAAA', hash: 'AAAA', iterations: 0);
    expect(PasswordHasher.verify('Campus2026!', noIterations), isFalse);
  });
}
