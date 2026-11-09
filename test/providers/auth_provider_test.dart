import 'dart:async';
import 'dart:io';

import 'package:campusconnect/core/utils/auth_failure.dart';
import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/services/auth_service.dart';
import 'package:campusconnect/services/device_session_service.dart';
import 'package:campusconnect/services/student_card_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

void main() {
  late MockAuthService service;
  late StreamController<AuthAccount?> authStream;
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
    authStream = StreamController<AuthAccount?>.broadcast();
    when(() => service.authStateChanges).thenAnswer((_) => authStream.stream);
    when(() => service.twoFactorPending).thenReturn(false);
    when(() => service.demoSmsCode).thenReturn(null);
    when(() => service.watchProfile(any()))
        .thenAnswer((_) => const Stream<AppUser?>.empty().asBroadcastStream());
    provider = AuthProvider(authService: service);
  });

  tearDown(() async {
    provider.dispose();
    await authStream.close();
  });

  Future<void> pump() => Future<void>.delayed(Duration.zero);

  const account = AuthAccount(uid: 'uid-1', email: 'amel@esprit.tn');

  group('auth state', () {
    test('starts unknown, then becomes visitor when signed out', () async {
      expect(provider.status, AuthStatus.unknown);
      authStream.add(null);
      await pump();
      expect(provider.status, AuthStatus.visitor);
      expect(provider.currentUser, isNull);
    });

    test('becomes authenticated and loads the profile when signed in',
        () async {
      when(() => service.fetchProfile('uid-1'))
          .thenAnswer((_) async => profile);
      authStream.add(account);
      await pump();
      expect(provider.status, AuthStatus.authenticated);
      expect(provider.currentUser, profile);
    });

    test('stays authenticated when the profile cannot be read', () async {
      when(() => service.fetchProfile(any()))
          .thenThrow(AuthFailure.fromCode('unknown'));
      authStream.add(account);
      await pump();
      expect(provider.status, AuthStatus.authenticated);
      expect(provider.currentUser, isNull);
    });

    test('signs out a disabled account and explains why', () async {
      final disabled = AppUser(
        id: 'uid-1',
        fullName: 'Amel Ben Salah',
        email: 'amel@esprit.tn',
        createdAt: DateTime(2025, 1, 1),
        disabled: true,
      );
      when(() => service.fetchProfile('uid-1'))
          .thenAnswer((_) async => disabled);
      when(() => service.signOut()).thenAnswer((_) async {});
      authStream.add(account);
      await pump();
      verify(() => service.signOut()).called(1);
      expect(provider.status, AuthStatus.visitor);
      expect(provider.currentUser, isNull);
      expect(provider.errorMessage,
          "Compte désactivé. Contacte l'administration.");
    });

    test('a pending two-factor sign-in is exposed as twoFactorRequired',
        () async {
      when(() => service.fetchProfile('uid-1'))
          .thenAnswer((_) async => profile);
      when(() => service.twoFactorPending).thenReturn(true);
      authStream.add(account);
      await pump();
      expect(provider.status, AuthStatus.authenticated);
      expect(provider.twoFactorRequired, isTrue);

      authStream.add(null);
      await pump();
      expect(provider.twoFactorRequired, isFalse);
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
          .thenAnswer((_) async => account);
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
      when(() => service.signInWithEmail(any(), any()))
          .thenThrow(StateError('boom'));
      expect(await provider.login('a@b.co', 'x'), isFalse);
      expect(provider.errorMessage, 'Une erreur est survenue. Réessayez.');
      expect(provider.errorCode, 'unknown');
    });

    test('a new attempt resets the previous error', () async {
      when(() => service.signInWithEmail(any(), any()))
          .thenThrow(AuthFailure.fromCode('user-not-found'));
      await provider.login('a@b.co', 'x');
      expect(provider.errorMessage, isNotNull);

      when(() => service.signInWithEmail(any(), any()))
          .thenAnswer((_) async => account);
      await provider.login('a@b.co', 'x');
      expect(provider.errorMessage, isNull);
      expect(provider.errorCode, isNull);
    });

    test('ignores a second submission while one is in flight', () async {
      final gate = Completer<AuthAccount>();
      when(() => service.signInWithEmail(any(), any()))
          .thenAnswer((_) => gate.future);

      final first = provider.login('a@b.co', 'x');
      expect(provider.isLoading, isTrue);
      expect(await provider.login('a@b.co', 'x'), isFalse);

      gate.complete(account);
      expect(await first, isTrue);
      verify(() => service.signInWithEmail(any(), any())).called(1);
    });

    test('clearError removes the message', () async {
      when(() => service.signInWithEmail(any(), any()))
          .thenThrow(AuthFailure.fromCode('user-disabled'));
      await provider.login('a@b.co', 'x');
      provider.clearError();
      expect(provider.errorMessage, isNull);
      expect(provider.errorCode, isNull);
    });
  });

  group('register', () {
    test('stores the new profile (no verification email)', () async {
      when(() => service.registerWithEmail(
            email: any(named: 'email'),
            password: any(named: 'password'),
            fullName: any(named: 'fullName'),
          )).thenAnswer((_) async => profile);

      final ok = await provider.register(
          fullName: 'amel', email: 'amel@esprit.tn', password: 'secret123');
      expect(ok, isTrue);
      expect(provider.currentUser, profile);
      verify(() => service.registerWithEmail(
          email: 'amel@esprit.tn',
          password: 'secret123',
          fullName: 'amel')).called(1);
    });

    test('reports a failed registration', () async {
      when(() => service.registerWithEmail(
            email: any(named: 'email'),
            password: any(named: 'password'),
            fullName: any(named: 'fullName'),
          )).thenThrow(AuthFailure.fromCode('email-already-in-use'));

      final ok = await provider.register(
          fullName: 'amel', email: 'a@b.co', password: 'secret123');
      expect(ok, isFalse);
      expect(provider.errorMessage, 'Cet email est déjà utilisé.');
      expect(provider.currentUser, isNull);
    });
  });

  group('biometrics', () {
    test('a refused biometric prompt yields biometric-denied', () async {
      when(() => service.authenticateWithBiometrics())
          .thenAnswer((_) async => false);
      expect(await provider.loginWithBiometrics(), isFalse);
      expect(provider.errorCode, 'biometric-denied');
    });

    test('accepted biometrics reopen the remembered session', () async {
      when(() => service.authenticateWithBiometrics())
          .thenAnswer((_) async => true);
      when(() => service.currentAccount).thenReturn(account);
      when(() => service.fetchProfile('uid-1'))
          .thenAnswer((_) async => profile);

      expect(await provider.loginWithBiometrics(), isTrue);
      expect(provider.status, AuthStatus.authenticated);
      expect(provider.currentUser?.fullName, 'Amel Ben Salah');
    });

    test(
        'accepted biometrics without a remembered session fail with no-session',
        () async {
      when(() => service.authenticateWithBiometrics())
          .thenAnswer((_) async => true);
      when(() => service.currentAccount).thenReturn(null);

      expect(await provider.loginWithBiometrics(), isFalse);
      expect(provider.errorCode, 'no-session');
      expect(provider.status, AuthStatus.unknown);
    });

    test(
        'checkBiometrics exposes the unlock button only with a sensor and a session',
        () async {
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

      await provider
          .checkBiometrics(); // inchangé : pas de notification superflue
      expect(notified, 1);
    });

    test('checkBiometrics swallows platform errors', () async {
      when(() => service.canUseBiometrics()).thenThrow(Exception('boom'));
      await provider.checkBiometrics();
      expect(provider.biometricsAvailable, isFalse);
      expect(provider.canUnlockWithBiometrics, isFalse);
    });
  });

  group('phone OTP', () {
    test('sendPhoneOtp keeps the normalized number', () async {
      when(() => service.sendPhoneOtp('20123456'))
          .thenAnswer((_) async => '+21620123456');
      expect(await provider.sendPhoneOtp('20123456'), isTrue);
      expect(provider.otpPhone, '+21620123456');
    });

    test('sendPhoneOtp failure leaves otpPhone empty', () async {
      when(() => service.sendPhoneOtp(any()))
          .thenThrow(AuthFailure.fromCode('invalid-phone-number'));
      expect(await provider.sendPhoneOtp('abc'), isFalse);
      expect(provider.otpPhone, isNull);
      expect(provider.errorCode, 'invalid-phone-number');
    });

    test('malformed codes are rejected locally without calling the service',
        () async {
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
      await provider.register(
          fullName: 'amel', email: 'amel@esprit.tn', password: 'secret123');

      when(() => service.sendPhoneOtp(any()))
          .thenAnswer((_) async => '+21620123456');
      await provider.sendPhoneOtp('20123456');
      when(() => service.verifyPhoneOtp('123456')).thenAnswer((_) async {});

      expect(await provider.verifyPhoneOtp('123456'), isTrue);
      expect(provider.currentUser?.isPhoneVerified, isTrue);
      expect(provider.currentUser?.phoneNumber, '+21620123456');
      expect(provider.otpPhone, isNull);
    });

    test('exposes the simulated SMS code of the service', () async {
      when(() => service.demoSmsCode).thenReturn('482913');
      expect(provider.demoSmsCode, '482913');
    });

    test('a valid code clears a pending two-factor sign-in', () async {
      when(() => service.fetchProfile('uid-1'))
          .thenAnswer((_) async => profile);
      when(() => service.twoFactorPending).thenReturn(true);
      authStream.add(account);
      await pump();
      expect(provider.twoFactorRequired, isTrue);

      when(() => service.verifyPhoneOtp('123456')).thenAnswer((_) async {});
      expect(await provider.verifyPhoneOtp('123456'), isTrue);
      expect(provider.twoFactorRequired, isFalse);
      expect(provider.status, AuthStatus.authenticated);
    });

    test('an expired code is reported and 2FA stays pending', () async {
      when(() => service.fetchProfile('uid-1'))
          .thenAnswer((_) async => profile);
      when(() => service.twoFactorPending).thenReturn(true);
      authStream.add(account);
      await pump();

      when(() => service.verifyPhoneOtp(any()))
          .thenThrow(AuthFailure.fromCode('session-expired'));
      expect(await provider.verifyPhoneOtp('123456'), isFalse);
      expect(provider.errorCode, 'session-expired');
      expect(provider.twoFactorRequired, isTrue);
    });

    test('a wrong code from the service is reported', () async {
      when(() => service.verifyPhoneOtp(any()))
          .thenThrow(AuthFailure.fromCode('invalid-verification-code'));
      expect(await provider.verifyPhoneOtp('000000'), isFalse);
      expect(provider.errorMessage, 'Code incorrect. Vérifiez et réessayez.');
    });
  });

  group('profile & session', () {
    test('updateProfile stores what the service returns (normalized)',
        () async {
      final updated = profile.copyWith(major: 'GL');
      final normalized = updated.copyWith(fullName: 'Amel Ben Salah');
      when(() => service.updateProfile(updated))
          .thenAnswer((_) async => normalized);
      expect(await provider.updateProfile(updated), isTrue);
      expect(provider.currentUser, normalized);
    });

    test('updateProfile failure keeps the previous user', () async {
      when(() => service.updateProfile(any()))
          .thenThrow(AuthFailure.fromCode('invalid-name'));
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

    test('exportMyData is empty without a user and delegates otherwise',
        () async {
      expect(await provider.exportMyData(), isEmpty);

      when(() => service.registerWithEmail(
            email: any(named: 'email'),
            password: any(named: 'password'),
            fullName: any(named: 'fullName'),
          )).thenAnswer((_) async => profile);
      await provider.register(
          fullName: 'amel', email: 'amel@esprit.tn', password: 'secret123');
      when(() => service.exportUserData('uid-1'))
          .thenAnswer((_) async => {'email': 'amel@esprit.tn'});

      expect(await provider.exportMyData(), {'email': 'amel@esprit.tn'});
    });

    test('deleteAccount delegates to the service', () async {
      when(() => service.deleteAccount()).thenAnswer((_) async {});
      expect(await provider.deleteAccount(), isTrue);
      verify(() => service.deleteAccount()).called(1);
    });

    test('deleteAccount without a password is refused by the service',
        () async {
      when(() => service.deleteAccount())
          .thenThrow(AuthFailure.fromCode('password-required'));
      expect(await provider.deleteAccount(), isFalse);
      expect(provider.errorCode, 'password-required');
    });
  });

  group('changePassword', () {
    test('delegates to the service', () async {
      when(() => service.changePassword(
          currentPassword: 'old12345',
          newPassword: 'new12345')).thenAnswer((_) async {});
      expect(
          await provider.changePassword(
              currentPassword: 'old12345', newPassword: 'new12345'),
          isTrue);
    });

    test('exposes the failure', () async {
      when(() => service.changePassword(
            currentPassword: any(named: 'currentPassword'),
            newPassword: any(named: 'newPassword'),
          )).thenThrow(AuthFailure.fromCode('wrong-password'));
      expect(
          await provider.changePassword(
              currentPassword: 'x', newPassword: 'new12345'),
          isFalse);
      expect(provider.errorCode, 'wrong-password');
    });
  });

  group('deleteAccount', () {
    setUp(() async {
      when(() => service.fetchProfile(any())).thenAnswer((_) async => profile);
      authStream.add(account);
      await pump();
    });

    test('passes the password and ends the session on success', () async {
      when(() => service.deleteAccount(password: 'secret123'))
          .thenAnswer((_) async {});
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
      authStream.add(AuthAccount(uid: user.id, email: user.email));
      await pump();
    }

    test('saves, updates the profile and removes the previous photo', () async {
      await signInWith(profile.copyWith(photoUrl: '/app/avatars/old.jpg'));
      when(() => storage.saveAvatar(file, uid: 'uid-1'))
          .thenAnswer((_) async => '/app/avatars/new.jpg');
      when(() => storage.delete('/app/avatars/old.jpg'))
          .thenAnswer((_) async {});

      expect(await provider.updateAvatar(file), isTrue);
      expect(provider.currentUser?.photoUrl, '/app/avatars/new.jpg');
      verify(() => storage.delete('/app/avatars/old.jpg')).called(1);
    });

    test('does not try to delete anything when there was no previous photo',
        () async {
      await signInWith(profile);
      when(() => storage.saveAvatar(file, uid: 'uid-1'))
          .thenAnswer((_) async => '/app/avatars/new.jpg');

      expect(await provider.updateAvatar(file), isTrue);
      verifyNever(() => storage.delete(any()));
    });

    test('a save failure is reported and nothing is written', () async {
      await signInWith(profile.copyWith(photoUrl: '/app/avatars/old.jpg'));
      when(() => storage.saveAvatar(file, uid: 'uid-1'))
          .thenThrow(AuthFailure.fromCode('invalid-file'));

      expect(await provider.updateAvatar(file), isFalse);
      expect(provider.errorCode, 'invalid-file');
      expect(provider.currentUser?.photoUrl, '/app/avatars/old.jpg');
      verifyNever(() => service.updateProfile(any()));
      verifyNever(() => storage.delete(any()));
    });

    test('without a signed-in user → no-session', () async {
      expect(await provider.updateAvatar(file), isFalse);
      expect(provider.errorCode, 'no-session');
      verifyNever(() => storage.saveAvatar(any(), uid: any(named: 'uid')));
    });
  });

  test('dispose cancels the auth subscription (no updates afterwards)',
      () async {
    final local = AuthProvider(authService: service);
    local.dispose();
    authStream.add(null);
    await pump();
    expect(local.status, AuthStatus.unknown);
  });
  group('live profile', () {
    late StreamController<AppUser?> profiles;

    setUp(() async {
      profiles = StreamController<AppUser?>.broadcast();
      when(() => service.watchProfile('uid-1'))
          .thenAnswer((_) => profiles.stream);
      when(() => service.fetchProfile('uid-1'))
          .thenAnswer((_) async => profile);
      when(() => service.signOut()).thenAnswer((_) async {});
      authStream.add(account);
      await pump();
    });
    tearDown(() => profiles.close());

    test('subscribes once authenticated', () {
      verify(() => service.watchProfile('uid-1')).called(1);
      expect(profiles.hasListener, isTrue);
    });

    test('an admin decision updates the current user live', () async {
      var notified = 0;
      provider.addListener(() => notified++);
      final verified = profile.copyWith(
        isVerifiedStudent: true,
        studentCard: StudentCard(
          status: StudentCardStatus.verified,
          imagePath: 'student_cards/uid-1/1.jpg',
          reviewedAt: DateTime(2026, 10, 28),
        ),
      );
      profiles.add(verified);
      await pump();
      expect(
          provider.currentUser!.studentCard.status, StudentCardStatus.verified);
      expect(provider.currentUser!.isVerifiedStudent, isTrue);
      expect(notified, greaterThan(0));
    });

    test('a disabled snapshot signs out with the account-disabled code',
        () async {
      profiles.add(AppUser(
        id: 'uid-1',
        fullName: profile.fullName,
        email: profile.email,
        createdAt: profile.createdAt,
        disabled: true,
      ));
      await pump();
      verify(() => service.signOut()).called(1);
      expect(provider.status, AuthStatus.visitor);
      expect(provider.currentUser, isNull);
      expect(provider.errorCode, AuthProvider.accountDisabledCode);
      expect(provider.errorMessage, contains('Compte désactivé'));
      expect(profiles.hasListener, isFalse);
    });

    test('logout and sign-out cancel the subscription', () async {
      expect(await provider.logout(), isTrue);
      expect(profiles.hasListener, isFalse);
    });

    test('a signed-out auth state cancels the subscription', () async {
      authStream.add(null);
      await pump();
      expect(profiles.hasListener, isFalse);
    });

    test('dispose cancels the subscription', () async {
      provider.dispose();
      expect(profiles.hasListener, isFalse);
      // tearDown disposes again: give it a fresh provider.
      provider = AuthProvider(authService: service);
    });
  });

  group('device history', () {
    late MockDeviceSessionService sessions;

    setUp(() {
      sessions = MockDeviceSessionService();
      provider.dispose();
      provider =
          AuthProvider(authService: service, deviceSessionService: sessions);
      when(() => sessions.recordLogin(any())).thenAnswer((_) async {});
      when(() => sessions.recordLogout(any())).thenAnswer((_) async {});
      when(() => sessions.deleteAll(any())).thenAnswer((_) async {});
    });

    test('a login is recorded in the history', () async {
      when(() => service.signInWithEmail(any(), any()))
          .thenAnswer((_) async => account);
      expect(await provider.login('amel@esprit.tn', 'secret123'), isTrue);
      verify(() => sessions.recordLogin('uid-1')).called(1);
    });

    test('a registration is recorded in the history', () async {
      when(() => service.registerWithEmail(
            email: any(named: 'email'),
            password: any(named: 'password'),
            fullName: any(named: 'fullName'),
          )).thenAnswer((_) async => profile);
      await provider.register(
          fullName: 'amel', email: 'amel@esprit.tn', password: 'secret123');
      verify(() => sessions.recordLogin('uid-1')).called(1);
    });

    test('a history failure never blocks the login', () async {
      when(() => service.signInWithEmail(any(), any()))
          .thenAnswer((_) async => account);
      when(() => sessions.recordLogin(any())).thenThrow(StateError('db'));
      expect(await provider.login('amel@esprit.tn', 'secret123'), isTrue);
      expect(provider.errorMessage, isNull);
    });

    test('logout is recorded before the session closes', () async {
      when(() => service.fetchProfile('uid-1'))
          .thenAnswer((_) async => profile);
      when(() => service.signOut()).thenAnswer((_) async {});
      authStream.add(account);
      await pump();

      expect(await provider.logout(), isTrue);
      verifyInOrder([
        () => sessions.recordLogout('uid-1'),
        () => service.signOut(),
      ]);
    });

    test('deleteAccount also erases the history of the account', () async {
      when(() => service.fetchProfile('uid-1'))
          .thenAnswer((_) async => profile);
      authStream.add(account);
      await pump();
      when(() => service.deleteAccount(
            password: 'secret123',
            beforeDelete: any(named: 'beforeDelete'),
          )).thenAnswer((inv) async {
        final cleanup =
            inv.namedArguments[#beforeDelete] as Future<void> Function(String);
        await cleanup('uid-1');
      });

      expect(await provider.deleteAccount(password: 'secret123'), isTrue);
      verify(() => sessions.deleteAll('uid-1')).called(1);
      expect(provider.status, AuthStatus.visitor);
    });

    test('exportMyData adds the history to the account export', () async {
      when(() => service.fetchProfile('uid-1'))
          .thenAnswer((_) async => profile);
      authStream.add(account);
      await pump();
      when(() => service.exportUserData('uid-1')).thenAnswer((_) async => {
            'account': {'email': 'amel@esprit.tn'}
          });
      when(() => sessions.export('uid-1')).thenAnswer((_) async => {
            'logins': [
              {'at': '2026-01-01T12:00:00.000'}
            ]
          });

      final export = await provider.exportMyData();
      expect(export['account'], {'email': 'amel@esprit.tn'});
      expect(export['logins'], hasLength(1));
    });

    test('exportMyData still returns the profile if the history fails',
        () async {
      when(() => service.fetchProfile('uid-1'))
          .thenAnswer((_) async => profile);
      authStream.add(account);
      await pump();
      when(() => service.exportUserData('uid-1')).thenAnswer((_) async => {
            'account': {'email': 'amel@esprit.tn'}
          });
      when(() => sessions.export('uid-1')).thenThrow(StateError('db'));

      expect(await provider.exportMyData(), {
        'account': {'email': 'amel@esprit.tn'}
      });
    });
  });

  group('student card', () {
    test('submits the card and keeps it pending on the current user', () async {
      final cards = MockStudentCardService();
      provider.dispose();
      provider = AuthProvider(
          authService: service,
          studentCardService: cards,
          clock: () => DateTime(2026, 1, 1));
      when(() => service.fetchProfile('uid-1'))
          .thenAnswer((_) async => profile);
      authStream.add(account);
      await pump();
      final file = File('card.jpg');
      final card = StudentCard.pending(
          imagePath: '/app/student_cards/uid-1/1.jpg',
          submittedAt: DateTime(2026, 1, 1));
      when(() =>
              cards.submit(uid: 'uid-1', photo: file, now: any(named: 'now')))
          .thenAnswer((_) async => card);

      expect(await provider.submitStudentCard(file), isTrue);
      expect(
          provider.currentUser!.studentCard.status, StudentCardStatus.pending);
    });

    test('without a signed-in user → no-session', () async {
      expect(await provider.submitStudentCard(File('card.jpg')), isFalse);
      expect(provider.errorCode, 'no-session');
    });
  });
}

class MockStudentCardService extends Mock implements StudentCardService {}

class MockDeviceSessionService extends Mock implements DeviceSessionService {}
