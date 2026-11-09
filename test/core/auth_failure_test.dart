import 'package:campusconnect/core/utils/auth_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps known codes to French messages', () {
    const expected = {
      'email-already-in-use': 'Cet email est déjà utilisé.',
      'wrong-password': 'Mot de passe incorrect.',
      'invalid-credential': 'Email ou mot de passe incorrect.',
      'user-not-found': 'Aucun compte avec cet email.',
      'user-disabled': 'Ce compte a été désactivé.',
      'too-many-requests': 'Trop de tentatives. Réessayez dans 5 minutes.',
      'invalid-verification-code': 'Code incorrect. Vérifiez et réessayez.',
      'session-expired': 'Le code a expiré. Demandez-en un nouveau.',
      'otp-not-sent': "Aucun code n'a été envoyé. Demandez-en un d'abord.",
    };
    expected.forEach((code, message) {
      final failure = AuthFailure.fromCode(code);
      expect(failure.code, code);
      expect(failure.message, message);
    });
  });

  test('unknown codes fall back to a generic message but keep the code', () {
    final failure = AuthFailure.fromCode('something-new');
    expect(failure.code, 'something-new');
    expect(failure.message, 'Une erreur est survenue. Réessayez.');
  });

  test('network codes no longer exist: there is no server', () {
    final failure = AuthFailure.fromCode('network-request-failed');
    expect(failure.message, 'Une erreur est survenue. Réessayez.');
  });

  test('fromCode keeps the cause for debugging only', () {
    final cause = StateError('détail interne');
    final failure = AuthFailure.fromCode('wrong-password', cause: cause);
    expect(failure.cause, same(cause));
    expect(failure.message, isNot(contains('interne')));
    expect(failure.toString(), contains('wrong-password'));
  });

  test('existing AuthFailure is returned unchanged', () {
    const original = AuthFailure('custom', 'Mon message');
    expect(identical(AuthFailure.from(original), original), isTrue);
  });

  test('arbitrary exceptions become an "unknown" failure without leaking details', () {
    final error = StateError('secret internal detail');
    final failure = AuthFailure.from(error);
    expect(failure.code, 'unknown');
    expect(failure.message, isNot(contains('secret')));
    expect(failure.cause, same(error));
  });
}
