import 'package:campusconnect/core/utils/auth_failure.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps known Firebase Auth codes to French messages', () {
    const expected = {
      'email-already-in-use': 'Cet email est déjà utilisé.',
      'wrong-password': 'Email ou mot de passe incorrect.',
      'invalid-credential': 'Email ou mot de passe incorrect.',
      'user-not-found': 'Aucun compte avec cet email.',
      'too-many-requests': 'Trop de tentatives. Réessayez dans quelques minutes.',
      'network-request-failed': 'Pas de connexion réseau.',
      'invalid-verification-code': 'Code incorrect. Vérifiez et réessayez.',
    };
    expected.forEach((code, message) {
      final failure = AuthFailure.from(FirebaseAuthException(code: code));
      expect(failure.code, code);
      expect(failure.message, message);
    });
  });

  test('unknown codes fall back to a generic message but keep the code', () {
    final failure = AuthFailure.from(FirebaseAuthException(code: 'something-new'));
    expect(failure.code, 'something-new');
    expect(failure.message, 'Une erreur est survenue. Réessayez.');
  });

  test('Firestore "unavailable" is reported as a network problem', () {
    final failure = AuthFailure.from(FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'));
    expect(failure.code, 'network-request-failed');
    expect(failure.message, 'Pas de connexion réseau.');
  });

  test('existing AuthFailure is returned unchanged', () {
    const original = AuthFailure('custom', 'Mon message');
    expect(identical(AuthFailure.from(original), original), isTrue);
  });

  test('arbitrary exceptions become an "unknown" failure without leaking details', () {
    final failure = AuthFailure.from(StateError('secret internal detail'));
    expect(failure.code, 'unknown');
    expect(failure.message, isNot(contains('secret')));
  });
}
