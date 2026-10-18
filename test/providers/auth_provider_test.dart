import 'dart:async';
import 'dart:io';

import 'package:campusconnect/core/utils/auth_failure.dart';
import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

void main() {
  late MockAuthService service;
  late StreamController<User?> authStream;
  late AuthProvider provider;

  final profile = AppUser(
    id: 'uid-1',
    fullName: 'Amel Ben Salah',
    email: 'amel@esprit.tn',
    createdAt: DateTime(2025, 1, 1),
  );

  setUpAll(() {
    registerFallbackValue(profile);
    registerFallbackValue(File('fallback.jpg'));
  });

  setUp(() {
    service = MockAuthService();
    authStream = StreamController<User?>.broadcast();
    when(() => service.authStateChanges).thenAnswer((_) => authStream.stream);
    provider = AuthProvider(authService: service);
  });

  tearDown(() async {
    provider.dispose();
    await authStream.close();
  });

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  group('auth state', () {
    test('starts unknown, then becomes visitor when signed out', () async {
      expect(provider.status, AuthStatus.unknown);
      authStream.add(null);
      await pump();
      expect(provider.status, AuthStatus.visitor);
      expect(provider.currentUser, isNull);
    });

    test('becomes authenticated and loads the profile when signed in', () async {
      when(() => service.fetchProfile('uid-1')).thenAnswer((_) async => profile);
      authStream.add(MockUser(uid: 'uid-1'));
      await pump();
      expect(provider.status, AuthStatus.authenticated);
      expect(provider.currentUser, profile);
    });

    test('stays authenticated when the profile cannot be loaded (offline)', () async {
      when(() => service.fetchProfile(any())).thenThrow(AuthFailure.fromCode('network-request-failed'));
      authStream.add(MockUser(uid: 'uid-1'));
      await pump();
      expect(provider.status, AuthStatus.authenticated);
      expect(provider.currentUser, isNull);
    });

    test('notifies listeners on changes', () async {
      var notifications = 0;
      provider.addListener(() => notifications++);
      authStream.add(null);
      await pump();
      expect(notifications, 1);
    });
  });

  group('login', () {
    test('returns true and clears loading on success', () async {
      when(() => service.signInWithEmail('a@b.co', 'secret123'))
          .thenAnswer((_) async => MockUserCredential());
      expect(await provider.login('a@b.co', 'secret123'), isTrue);
      expect(provider.isLoading, isFalse);
      expect(provider.errorMessage, isNull);
    });

    test('exposes message and code on failure', () async {
      when(() => service.signInWithEmail(any(), any()))
          .thenThrow(AuthFailure.fromCode('invalid-credential'));
      expect(await provider.login('a@b.co', 'bad'), isFalse);
      expect(provider.errorMessage, 'Email ou mot de passe incorrect.');
      expect(provider.errorCode, 'invalid-credential');
      expect(provider.isLoading, isFalse);
    });

    test('wraps unexpected exceptions with a generic message', () async {
      when(() => service.signInWithEmail(any(), any())).thenThrow(StateError('boom'));
      expect(await provider.login('a@b.co', 'x'), isFalse);
      expect(provider.errorMessage, 'Une erreur est survenue. Réessayez.');
      expect(provider.errorCode, 'unknown');
    });

    test('a new attempt resets the previous error', () async {
      when(() => service.signInWithEmail(any(), any()))
          .thenThrow(AuthFailure.fromCode('user-not-found'));
      await provider.login('a@b.co', 'x');
      expect(provider.errorMessage, isNotNull);

      when(() => service.signInWithEmail(any(), any())).thenAnswer((_) async => MockUserCredential());
      await provider.login('a@b.co', 'x');
      expect(provider.errorMessage, isNull);
      expect(provider.errorCode, isNull);
    });

    test('ignores a second submission while one is in flight', () async {
      final gate = Completer<UserCredential>();
      when(() => service.signInWithEmail(any(), any())).thenAnswer((_) => gate.future);

      final first = provider.login('a@b.co', 'x');
      expect(provider.isLoading, isTrue);
      expect(await provider.login('a@b.co', 'x'), isFalse);

      gate.complete(MockUserCredential());
      expect(await first, isTrue);
      verify(() => service.signInWithEmail(any(), any())).called(1);
    });

    test('clearError removes the message', () async {
      when(() => service.signInWithEmail(any(), any())).thenThrow(AuthFailure.fromCode('user-disabled'));
      await provider.login('a@b.co', 'x');
      provider.clearError();
      expect(provider.errorMessage, isNull);
      expect(provider.errorCode, isNull);
    });
  });

  group('register', () {
    test('stores the new profile and sends the verification email', () async {
      when(() => service.registerWithEmail(
            email: any(named: 'email'),
            password: any(named: 'password'),
            fullName: any(named: 'fullName'),
          )).thenAnswer((_) async => profile);
      when(() => service.sendEmailVerification()).thenAnswer((_) async {});

      final ok = await provider.register(fullName: 'amel', email: 'amel@esprit.tn', password: 'secret123');
      expect(ok, isTrue);
      expect(provider.currentUser, profile);
      verify(() => service.sendEmailVerification()).called(1);
    });

    test('does not send a verification email when registration fails', () async {
      when(() => service.registerWithEmail(
            email: any(named: 'email'),
            password: any(named: 'password'),
            fullName: any(named: 'fullName'),
          )).thenThrow(AuthFailure.fromCode('email-already-in-use'));

      final ok = await provider.register(fullName: 'amel', email: 'a@b.co', password: 'secret123');
      expect(ok, isFalse);
      expect(provider.errorMessage, 'Cet email est déjà utilisé.');
      verifyNever(() => service.sendEmailVerification());
    });
  });

  group('google & biometrics', () {
    test('a cancelled Google sign-in is not an error', () async {
      when(() => service.signInWithGoogle()).thenAnswer((_) async => null);
      expect(await provider.loginWithGoogle(), isTrue);
      expect(provider.errorMessage, isNull);
    });

    test('Google errors are surfaced', () async {
      when(() => service.signInWithGoogle())
          .thenThrow(AuthFailure.fromCode('account-exists-with-different-credential'));
      expect(await provider.loginWithGoogle(), isFalse);
      expect(provider.errorCode, 'account-exists-with-different-credential');
    });

    test('a refused biometric prompt yields biometric-denied', () async {
      when(() => service.authenticateWithBiometrics()).thenAnswer((_) async => false);
      expect(await provider.loginWithBiometrics(), isFalse);
      expect(provider.errorCode, 'biometric-denied');
    });

    test('accepted biometrics reopen the remembered session', () async {
      when(() => service.authenticateWithBiometrics()).thenAnswer((_) async => true);
      when(() => service.currentFirebaseUser).thenReturn(MockUser(uid: 'uid-1', email: 'amel@esprit.tn'));
      when(() => service.fetchProfile('uid-1')).thenAnswer((_) async => profile);

      expect(await provider.loginWithBiometrics(), isTrue);
      expect(provider.status, AuthStatus.authenticated);
      expect(provider.currentUser?.fullName, 'Amel Ben Salah');
    });

    test('accepted biometrics without a remembered session fail with no-session', () async {
      when(() => service.authenticateWithBiometrics()).thenAnswer((_) async => true);
      when(() => service.currentFirebaseUser).thenReturn(null);

      expect(await provider.loginWithBiometrics(), isFalse);
      expect(provider.errorCode, 'no-session');
      expect(provider.status, AuthStatus.unknown);
    });

    test('checkBiometrics exposes the unlock button only with a sensor and a session', () async {
      when(() => service.canUseBiometrics()).thenAnswer((_) async => true);
      when(() => service.hasRestorableSession).thenReturn(true);
      var notified = 0;
      provider.addListener(() => notified++);

      await provider.checkBiometrics();
      expect(provider.biometricsAvailable, isTrue);
      expect(provider.canUnlockWithBiometrics, isTrue);
      expect(notified, 1);

      when(() => service.hasRestorableSession).thenReturn(false);
      expect(provider.canUnlockWithBiometrics, isFalse);

      await provider.checkBiometrics(); // inchangé : pas de notification superflue
      expect(notified, 1);
    });

    test('checkBiometrics swallows platform errors', () async {
      when(() => service.canUseBiometrics()).thenThrow(Exception('boom'));
      await provider.checkBiometrics();
      expect(provider.biometricsAvailable, isFalse);
      expect(provider.canUnlockWithBiometrics, isFalse);
    });
  });

  group('password reset', () {
    test('succeeds', () async {
      when(() => service.sendPasswordReset('a@b.co')).thenAnswer((_) async {});
      expect(await provider.sendPasswordReset('a@b.co'), isTrue);
    });

    test('reports user-not-found with its code so the UI can stay neutral', () async {
      when(() => service.sendPasswordReset(any())).thenThrow(AuthFailure.fromCode('user-not-found'));
      expect(await provider.sendPasswordReset('ghost@b.co'), isFalse);
      expect(provider.errorCode, 'user-not-found');
    });
  });

  group('phone OTP', () {
    test('sendPhoneOtp keeps the normalized number', () async {
      when(() => service.sendPhoneOtp('20123456')).thenAnswer((_) async => '+21620123456');
      expect(await provider.sendPhoneOtp('20123456'), isTrue);
      expect(provider.otpPhone, '+21620123456');
    });

    test('sendPhoneOtp failure leaves otpPhone empty', () async {
      when(() => service.sendPhoneOtp(any())).thenThrow(AuthFailure.fromCode('invalid-phone-number'));
      expect(await provider.sendPhoneOtp('abc'), isFalse);
      expect(provider.otpPhone, isNull);
      expect(provider.errorCode, 'invalid-phone-number');
    });

    test('malformed codes are rejected locally without calling the service', () async {
      expect(await provider.verifyPhoneOtp('12ab'), isFalse);
      expect(provider.errorCode, 'invalid-verification-code');
      verifyNever(() => service.verifyPhoneOtp(any()));
    });

    test('a valid code marks the phone as verified', () async {
      when(() => service.registerWithEmail(
            email: any(named: 'email'),
            password: any(named: 'password'),
            fullName: any(named: 'fullName'),
          )).thenAnswer((_) async => profile);
      when(() => service.sendEmailVerification()).thenAnswer((_) async {});
      await provider.register(fullName: 'amel', email: 'amel@esprit.tn', password: 'secret123');

      when(() => service.sendPhoneOtp(any())).thenAnswer((_) async => '+21620123456');
      await provider.sendPhoneOtp('20123456');
      when(() => service.verifyPhoneOtp('123456')).thenAnswer((_) async {});

      expect(await provider.verifyPhoneOtp('123456'), isTrue);
      expect(provider.currentUser?.isPhoneVerified, isTrue);
      expect(provider.currentUser?.phoneNumber, '+21620123456');
      expect(provider.otpPhone, isNull);
    });

    test('a wrong code from the backend is reported', () async {
      when(() => service.verifyPhoneOtp(any())).thenThrow(AuthFailure.fromCode('invalid-verification-code'));
      expect(await provider.verifyPhoneOtp('000000'), isFalse);
      expect(provider.errorMessage, 'Code incorrect. Vérifiez et réessayez.');
    });
  });

  group('profile & session', () {
    test('updateProfile stores what the service returns (normalized)', () async {
      final updated = profile.copyWith(major: 'GL');
      final normalized = updated.copyWith(fullName: 'Amel Ben Salah');
      when(() => service.updateProfile(updated)).thenAnswer((_) async => normalized);
      expect(await provider.updateProfile(updated), isTrue);
      expect(provider.currentUser, normalized);
    });

    test('updateProfile failure keeps the previous user', () async {
      when(() => service.updateProfile(any())).thenThrow(AuthFailure.fromCode('network-request-failed'));
      expect(await provider.updateProfile(profile), isFalse);
      expect(provider.currentUser, isNull);
    });

    test('logout signs out and switches to visitor', () async {
      when(() => service.signOut()).thenAnswer((_) async {});
      expect(await provider.logout(), isTrue);
      expect(provider.status, AuthStatus.visitor);
      expect(provider.currentUser, isNull);
    });

    test('continueAsVisitor sets visitor status', () async {
      await provider.continueAsVisitor();
      expect(provider.status, AuthStatus.visitor);
    });

    test('exportMyData is empty without a user and delegates otherwise', () async {
      expect(await provider.exportMyData(), isEmpty);

      when(() => service.registerWithEmail(
            email: any(named: 'email'),
            password: any(named: 'password'),
            fullName: any(named: 'fullName'),
          )).thenAnswer((_) async => profile);
      when(() => service.sendEmailVerification()).thenAnswer((_) async {});
      await provider.register(fullName: 'amel', email: 'amel@esprit.tn', password: 'secret123');
      when(() => service.exportUserData('uid-1')).thenAnswer((_) async => {'email': 'amel@esprit.tn'});

      expect(await provider.exportMyData(), {'email': 'amel@esprit.tn'});
    });

    test('deleteAccount delegates to the service', () async {
      when(() => service.deleteAccount()).thenAnswer((_) async {});
      expect(await provider.deleteAccount(), isTrue);
      verify(() => service.deleteAccount()).called(1);
    });
  });

  group('account flags', () {
    test('email verification and password provider come from the Firebase user', () async {
      when(() => service.fetchProfile(any())).thenAnswer((_) async => profile);
      authStream.add(MockUser(uid: 'uid-1', isEmailVerified: false, providerData: [FakeUserInfo('password')]));
      await pump();
      expect(provider.emailVerified, isFalse);
      expect(provider.hasPasswordProvider, isTrue);

      authStream.add(MockUser(uid: 'uid-1', isEmailVerified: true, providerData: [FakeUserInfo('google.com')]));
      await pump();
      expect(provider.emailVerified, isTrue);
      expect(provider.hasPasswordProvider, isFalse);
    });

    test('flags reset on sign-out', () async {
      when(() => service.fetchProfile(any())).thenAnswer((_) async => profile);
      authStream.add(MockUser(uid: 'uid-1', isEmailVerified: true, providerData: [FakeUserInfo('password')]));
      await pump();
      authStream.add(null);
      await pump();
      expect(provider.emailVerified, isFalse);
      expect(provider.hasPasswordProvider, isFalse);
    });
  });

  group('email verification', () {
    late DateTime now;

    setUp(() {
      now = DateTime(2026, 1, 1, 12);
      provider.dispose();
      provider = AuthProvider(authService: service, clock: () => now);
      when(() => service.sendEmailVerification()).thenAnswer((_) async {});
    });

    test('register starts the resend cooldown', () async {
      when(() => service.registerWithEmail(
            email: any(named: 'email'),
            password: any(named: 'password'),
            fullName: any(named: 'fullName'),
          )).thenAnswer((_) async => profile);

      await provider.register(fullName: 'amel', email: 'amel@esprit.tn', password: 'secret123');
      expect(provider.hasPasswordProvider, isTrue);
      expect(provider.canResendVerification, isFalse);
      expect(provider.verificationCooldownLeft, AuthProvider.verificationCooldown);

      now = now.add(const Duration(seconds: 61));
      expect(provider.canResendVerification, isTrue);
      expect(provider.verificationCooldownLeft, Duration.zero);
    });

    test('resend is refused during the cooldown and allowed afterwards', () async {
      expect(await provider.resendVerificationEmail(), isTrue);
      verify(() => service.sendEmailVerification()).called(1);

      now = now.add(const Duration(seconds: 20));
      expect(await provider.resendVerificationEmail(), isFalse);
      expect(provider.errorCode, 'verification-cooldown');
      expect(provider.errorMessage, contains('40 s'));
      verifyNever(() => service.sendEmailVerification());

      now = now.add(const Duration(seconds: 40));
      expect(await provider.resendVerificationEmail(), isTrue);
      verify(() => service.sendEmailVerification()).called(1);
    });

    test('refreshEmailVerification reloads and reports the status', () async {
      when(() => service.reloadUser()).thenAnswer((_) async => true);
      expect(await provider.refreshEmailVerification(), isTrue);
      expect(provider.emailVerified, isTrue);

      when(() => service.reloadUser()).thenAnswer((_) async => false);
      expect(await provider.refreshEmailVerification(), isFalse);
      expect(provider.emailVerified, isFalse);
      expect(provider.errorMessage, isNull);
    });

    test('refreshEmailVerification surfaces failures', () async {
      when(() => service.reloadUser()).thenThrow(AuthFailure.fromCode('network-request-failed'));
      expect(await provider.refreshEmailVerification(), isFalse);
      expect(provider.errorCode, 'network-request-failed');
    });
  });

  group('changePassword', () {
    test('delegates to the service', () async {
      when(() => service.changePassword(currentPassword: 'old12345', newPassword: 'new12345'))
          .thenAnswer((_) async {});
      expect(await provider.changePassword(currentPassword: 'old12345', newPassword: 'new12345'), isTrue);
    });

    test('exposes the failure', () async {
      when(() => service.changePassword(
            currentPassword: any(named: 'currentPassword'),
            newPassword: any(named: 'newPassword'),
          )).thenThrow(AuthFailure.fromCode('wrong-password'));
      expect(await provider.changePassword(currentPassword: 'x', newPassword: 'new12345'), isFalse);
      expect(provider.errorCode, 'wrong-password');
    });
  });

  group('deleteAccount', () {
    setUp(() async {
      when(() => service.fetchProfile(any())).thenAnswer((_) async => profile);
      authStream.add(MockUser(uid: 'uid-1'));
      await pump();
    });

    test('passes the password and ends the session on success', () async {
      when(() => service.deleteAccount(password: 'secret123')).thenAnswer((_) async {});
      expect(await provider.deleteAccount(password: 'secret123'), isTrue);
      expect(provider.status, AuthStatus.visitor);
      expect(provider.currentUser, isNull);
    });

    test('keeps the session when the deletion fails', () async {
      when(() => service.deleteAccount(password: any(named: 'password')))
          .thenThrow(AuthFailure.fromCode('wrong-password'));
      expect(await provider.deleteAccount(password: 'bad'), isFalse);
      expect(provider.status, AuthStatus.authenticated);
      expect(provider.currentUser, profile);
      expect(provider.errorCode, 'wrong-password');
    });
  });

  group('updateAvatar', () {
    late MockStorageService storage;
    final file = File('avatar.jpg');

    setUp(() {
      storage = MockStorageService();
      provider.dispose();
      provider = AuthProvider(authService: service, storageService: storage);
      when(() => service.updateProfile(any()))
          .thenAnswer((inv) async => inv.positionalArguments.first as AppUser);
    });

    Future<void> signInWith(AppUser user) async {
      when(() => service.fetchProfile(any())).thenAnswer((_) async => user);
      authStream.add(MockUser(uid: user.id));
      await pump();
    }

    test('uploads, updates the profile and removes the previous photo', () async {
      await signInWith(profile.copyWith(photoUrl: 'https://old'));
      when(() => storage.uploadAvatar(file, uid: 'uid-1')).thenAnswer((_) async => 'https://new');
      when(() => storage.deleteByUrl('https://old')).thenAnswer((_) async {});

      expect(await provider.updateAvatar(file), isTrue);
      expect(provider.currentUser?.photoUrl, 'https://new');
      verify(() => storage.deleteByUrl('https://old')).called(1);
    });

    test('does not try to delete anything when there was no previous photo', () async {
      await signInWith(profile);
      when(() => storage.uploadAvatar(file, uid: 'uid-1')).thenAnswer((_) async => 'https://new');

      expect(await provider.updateAvatar(file), isTrue);
      verifyNever(() => storage.deleteByUrl(any()));
    });

    test('an upload failure is reported and nothing is written', () async {
      await signInWith(profile.copyWith(photoUrl: 'https://old'));
      when(() => storage.uploadAvatar(file, uid: 'uid-1')).thenThrow(AuthFailure.fromCode('invalid-file'));

      expect(await provider.updateAvatar(file), isFalse);
      expect(provider.errorCode, 'invalid-file');
      expect(provider.currentUser?.photoUrl, 'https://old');
      verifyNever(() => service.updateProfile(any()));
      verifyNever(() => storage.deleteByUrl(any()));
    });

    test('without a signed-in user → no-session', () async {
      expect(await provider.updateAvatar(file), isFalse);
      expect(provider.errorCode, 'no-session');
      verifyNever(() => storage.uploadAvatar(any(), uid: any(named: 'uid')));
    });
  });

  test('dispose cancels the auth subscription (no updates afterwards)', () async {
    final local = AuthProvider(authService: service);
    local.dispose();
    authStream.add(null);
    await pump();
    expect(local.status, AuthStatus.unknown);
  });
}

class MockUserCredential extends Mock implements UserCredential {}
