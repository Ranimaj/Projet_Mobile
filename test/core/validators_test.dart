import 'package:campusconnect/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('student id', () {
    test('null and empty are allowed', () {
      expect(Validators.studentId(null), isNull);
      expect(Validators.studentId('  '), isNull);
    });
    test('accepts 6 to 12 alphanumerics', () {
      expect(Validators.studentId('ABC123'), isNull);
      expect(Validators.studentId(' 19A123456789 '), isNull);
    });
    test('rejects other values', () {
      const msg = 'Identifiant invalide (6 à 12 caractères)';
      expect(Validators.studentId('A1'), msg);
      expect(Validators.studentId('1234567890123'), msg);
      expect(Validators.studentId('ab-1234'), msg);
    });
  });

  group('email', () {
    test('accepts valid addresses', () {
      for (final e in ['a@b.co', 'prenom.nom@esprit.tn', ' User+tag@sub.domain.com ']) {
        expect(Validators.email(e), isNull, reason: e);
      }
    });

    test('rejects empty and malformed addresses', () {
      expect(Validators.email(null), 'Email requis');
      expect(Validators.email('   '), 'Email requis');
      for (final e in ['abc', 'a@', '@b.com', 'a@b', 'a b@c.com', 'a@b..com', 'a@@b.com']) {
        expect(Validators.email(e), 'Email invalide', reason: e);
      }
    });
  });

  group('passwords', () {
    test('login only requires a non-empty password', () {
      expect(Validators.loginPassword(''), isNotNull);
      expect(Validators.loginPassword(null), isNotNull);
      expect(Validators.loginPassword('x'), isNull);
    });

    test('new password enforces length, letter and digit', () {
      expect(Validators.newPassword(''), 'Mot de passe requis');
      expect(Validators.newPassword('abc123'), '8 caractères minimum');
      expect(Validators.newPassword('12345678'), 'Ajoutez au moins une lettre');
      expect(Validators.newPassword('abcdefgh'), 'Ajoutez au moins un chiffre');
      expect(Validators.newPassword('abcdefg1'), isNull);
    });

    test('confirmPassword compares against the live original', () {
      var original = 'secret123';
      final validate = Validators.confirmPassword(() => original);
      expect(validate(''), 'Confirmation requise');
      expect(validate('other'), 'Les mots de passe ne correspondent pas');
      expect(validate('secret123'), isNull);
      original = 'changed456';
      expect(validate('secret123'), isNotNull);
    });

    test('strength score is 0 for empty and capped between 1 and 4', () {
      expect(Validators.passwordStrength(''), 0);
      expect(Validators.passwordStrength('a'), 1);
      expect(Validators.passwordStrength('abcdefgh'), 1);
      expect(Validators.passwordStrength('abcdefg1'), 2);
      expect(Validators.passwordStrength('Abcdefg1'), 3);
      expect(Validators.passwordStrength('Abcdefg1!'), 4);
    });
  });

  group('full name', () {
    test('validates length and characters', () {
      expect(Validators.fullName(''), 'Nom requis');
      expect(Validators.fullName('Al'), 'Nom trop court');
      expect(Validators.fullName('A' * 61), 'Nom trop long');
      expect(Validators.fullName('John3 Doe'), 'Caractères non autorisés');
      expect(Validators.fullName('Amel Ben Salah'), isNull);
      expect(Validators.fullName("Jean-Luc O'Brien"), isNull);
    });

    test('normalizes spacing and capitalisation', () {
      expect(Validators.normalizeFullName('  amel   BEN  salah '), 'Amel Ben Salah');
      expect(Validators.normalizeFullName(''), '');
    });
  });

  group('phone', () {
    test('normalizes local, international and 00-prefixed numbers', () {
      expect(Validators.normalizePhone('20 123 456'), '+21620123456');
      expect(Validators.normalizePhone('20.123.456'), '+21620123456');
      expect(Validators.normalizePhone('+216 20 123 456'), '+21620123456');
      expect(Validators.normalizePhone('0033 6 12 34 56 78'), '+33612345678');
      expect(Validators.normalizePhone('(+1) 415-555-2671'), '+14155552671');
    });

    test('returns null for invalid numbers', () {
      for (final p in ['', 'abc', '1234567', '+0123456789', '+12', '123456789']) {
        expect(Validators.normalizePhone(p), isNull, reason: p);
      }
    });

    test('validator wraps normalization', () {
      expect(Validators.phone(''), 'Numéro requis');
      expect(Validators.phone('12'), isNotNull);
      expect(Validators.phone('20123456'), isNull);
    });
  });

  group('otp', () {
    test('requires exactly 6 digits', () {
      expect(Validators.otp(null), isNotNull);
      expect(Validators.otp('12345'), isNotNull);
      expect(Validators.otp('1234567'), isNotNull);
      expect(Validators.otp('12a456'), isNotNull);
      expect(Validators.otp('123456'), isNull);
      expect(Validators.otp(' 123456 '), isNull);
    });
  });

  test('normalizeEmail trims and lowercases', () {
    expect(Validators.normalizeEmail('  Prenom.NOM@Esprit.TN '), 'prenom.nom@esprit.tn');
  });
}
