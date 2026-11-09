import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:campusconnect/core/constants/app_constants.dart';
import 'package:campusconnect/core/utils/auth_failure.dart';
import 'package:campusconnect/core/utils/local_database.dart';
import 'package:campusconnect/core/utils/password_hasher.dart';
import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/services/auth_service.dart';
import 'package:campusconnect/services/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/local_db.dart';
import '../helpers/mocks.dart';

class MockLocalAuth extends Mock implements LocalAuthentication {}

Matcher failsWith(String code) => throwsA(isA<AuthFailure>().having((f) => f.code, 'code', code));

void main() {
  late LocalStore store;
  late MockStorageService files;
  late DateTime now;
  late AuthService service;

  setUpAll(() => registerFallbackValue(const AuthenticationOptions()));

  AuthService build({LocalAuthentication Function()? localAuth}) => AuthService(
        store: store,
        storage: files,
        hasher: PasswordHasher(iterations: 1),
        random: Random(7),
        clock: () => now,
        localAuthFactory: localAuth,
      );

  setUp(() async {
    await openTestDatabase();
    store = LocalStore();
    files = MockStorageService();
    when(() => files.delete(any())).thenAnswer((_) async {});
    now = DateTime(2026, 3, 1, 10);
    service = build();
  });

  tearDown(closeTestDatabase);

  Map<String, dynamic>? userDoc(String uid) => store.get(AppConstants.usersCollection, uid);
  Map<String, dynamic>? accountDoc(String uid) => store.get(AuthService.accountsCollection, uid);

  Future<AppUser> signUp({String email = 'amel@esprit.tn', String password = 'secret123'}) =>
      service.registerWithEmail(email: email, password: password, fullName: 'Amel Test');

  /// Profil avec la double authentification active et un numéro vérifié.
  Future<AppUser> signUpWithTwoFactor() async {
    final user = await signUp();
    await store.update(AppConstants.usersCollection, user.id, {
      'twoFactorEnabled': true,
      'isPhoneVerified': true,
      'phoneNumber': '+21620123456',
    });
    await service.signOut();
    return user;
  }

  group('registerWithEmail', () {
    test('creates the account and a normalized profile, then opens the session', () async {
      final user = await service.registerWithEmail(
        email: '  Amel.BenSalah@Esprit.TN ',
        password: 'secret123',
        fullName: '  amel   ben salah ',
      );

      expect(user.email, 'amel.bensalah@esprit.tn');
      expect(user.fullName, 'Amel Ben Salah');
      expect(service.currentAccount, AuthAccount(uid: user.id, email: 'amel.bensalah@esprit.tn'));
      expect(service.twoFactorPending, isFalse);

      final stored = userDoc(user.id)!;
      expect(stored['fullName'], 'Amel Ben Salah');
      expect(stored['role'], 'student');
      expect(stored['isPhoneVerified'], false);
    });

    test('stores a PBKDF2 hash, never the password', () async {
      final user = await signUp();
      final account = accountDoc(user.id)!;
      expect(account['email'], 'amel@esprit.tn');
      expect(jsonEncode(AuthService.jsonSafe(account)), isNot(contains('secret123')));
      final hash = PasswordHash.fromMap(Map<String, dynamic>.from(account['password'] as Map))!;
      expect(PasswordHasher.verify('secret123', hash), isTrue);
    });

    test('a duplicate email (any case) is rejected and nothing is created', () async {
      await signUp();
      await service.signOut();

      await expectLater(() => signUp(email: ' AMEL@esprit.tn'), failsWith('email-already-in-use'));
      expect(store.all(AuthService.accountsCollection), hasLength(1));
      expect(store.all(AppConstants.usersCollection), hasLength(1));
      expect(service.currentAccount, isNull);
    });

    test('rejects an invalid email or a weak password', () async {
      await expectLater(() => signUp(email: 'nope'), failsWith('invalid-email'));
      await expectLater(() => signUp(password: 'abc'), failsWith('weak-password'));
      expect(store.all(AuthService.accountsCollection), isEmpty);
    });
  });

  group('signInWithEmail', () {
    test('signs in with a trimmed, lowercased email (password untouched)', () async {
      final user = await signUp();
      await service.signOut();

      final account = await service.signInWithEmail('  AMEL@Esprit.tn ', 'secret123');

      expect(account, AuthAccount(uid: user.id, email: 'amel@esprit.tn'));
      expect(service.currentAccount, account);
      expect(parseDate(accountDoc(user.id)!['lastSignInAt']), now);
      await expectLater(() => service.signInWithEmail('amel@esprit.tn', 'SECRET123'), failsWith('invalid-credential'));
    });

    test('a wrong password or an unknown email give the same failure', () async {
      await signUp();
      await service.signOut();

      await expectLater(() => service.signInWithEmail('amel@esprit.tn', 'wrong1234'), failsWith('invalid-credential'));
      await expectLater(() => service.signInWithEmail('ghost@esprit.tn', 'secret123'), failsWith('invalid-credential'));
      expect(service.currentAccount, isNull);
    });

    test('locks the email after 5 failures in 5 minutes, then unlocks', () async {
      await signUp();
      await service.signOut();

      for (var i = 0; i < AuthService.maxFailedAttempts; i++) {
        await expectLater(() => service.signInWithEmail('amel@esprit.tn', 'bad$i'), failsWith('invalid-credential'));
      }
      // Même le bon mot de passe est refusé pendant le blocage.
      await expectLater(() => service.signInWithEmail('amel@esprit.tn', 'secret123'), failsWith('too-many-requests'));

      now = now.add(AuthService.lockout + const Duration(seconds: 1));
      await service.signInWithEmail('amel@esprit.tn', 'secret123');
      expect(service.currentAccount, isNotNull);
    });

    test('failures older than the window do not count, and a success resets them', () async {
      await signUp();
      await service.signOut();

      for (var i = 0; i < 4; i++) {
        await expectLater(() => service.signInWithEmail('amel@esprit.tn', 'bad'), failsWith('invalid-credential'));
      }
      await service.signInWithEmail('amel@esprit.tn', 'secret123');
      await service.signOut();
      for (var i = 0; i < 4; i++) {
        await expectLater(() => service.signInWithEmail('amel@esprit.tn', 'bad'), failsWith('invalid-credential'));
      }
      await service.signInWithEmail('amel@esprit.tn', 'secret123');
      expect(service.currentAccount, isNotNull);
    });

    test('the lockout is per email', () async {
      await signUp();
      await signUp(email: 'sami@esprit.tn');
      await service.signOut();

      for (var i = 0; i < AuthService.maxFailedAttempts; i++) {
        await expectLater(() => service.signInWithEmail('amel@esprit.tn', 'bad'), failsWith('invalid-credential'));
      }
      await service.signInWithEmail('sami@esprit.tn', 'secret123');
      expect(service.currentAccount!.email, 'sami@esprit.tn');
    });

    test('a disabled account cannot sign in', () async {
      final user = await signUp();
      await service.signOut();
      await store.update(AppConstants.usersCollection, user.id, {'disabled': true});

      await expectLater(() => service.signInWithEmail('amel@esprit.tn', 'secret123'), failsWith('user-disabled'));
      expect(service.currentAccount, isNull);
    });

    test('with 2FA on and a verified phone, the session opens pending the code', () async {
      await signUpWithTwoFactor();

      await service.signInWithEmail('amel@esprit.tn', 'secret123');
      expect(service.currentAccount, isNotNull);
      expect(service.twoFactorPending, isTrue);
    });

    test('2FA without a verified phone does not block the login', () async {
      final user = await signUp();
      await store.update(AppConstants.usersCollection, user.id, {'twoFactorEnabled': true});
      await service.signOut();

      await service.signInWithEmail('amel@esprit.tn', 'secret123');
      expect(service.twoFactorPending, isFalse);
    });
  });

  group('session', () {
    test('authStateChanges emits the current account on listen, then sign-in / sign-out', () async {
      final events = <AuthAccount?>[];
      final sub = service.authStateChanges.listen(events.add);
      await Future<void>.delayed(Duration.zero);
      final user = await signUp();
      await service.signOut();
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(events, [null, AuthAccount(uid: user.id, email: 'amel@esprit.tn'), null]);
    });

    test('the session survives an app restart (same SQLite file)', () async {
      await closeTestDatabase();
      final dir = await Directory.systemTemp.createTemp('auth_session');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/auth.db';
      await openTestDatabase(path: path);
      final user = await signUp();
      expect(service.hasRestorableSession, isTrue);

      await LocalDatabase.instance.close();
      await openTestDatabase(path: path);
      final restarted = build();

      expect(restarted.currentAccount, AuthAccount(uid: user.id, email: 'amel@esprit.tn'));
      expect(restarted.hasRestorableSession, isTrue);
      expect(await restarted.authStateChanges.first, restarted.currentAccount);
    });

    test('a pending 2FA also survives the restart', () async {
      await signUpWithTwoFactor();
      await service.signInWithEmail('amel@esprit.tn', 'secret123');

      expect(build().twoFactorPending, isTrue);
    });

    test('signOut forgets the session and the pending 2FA', () async {
      await signUpWithTwoFactor();
      await service.signInWithEmail('amel@esprit.tn', 'secret123');

      await service.signOut();
      expect(service.currentAccount, isNull);
      expect(service.hasRestorableSession, isFalse);
      expect(service.twoFactorPending, isFalse);
    });

    test('a session whose account was deleted is not restored', () async {
      final user = await signUp();
      await store.delete(AuthService.accountsCollection, user.id);
      expect(service.currentAccount, isNull);
    });
  });

  group('profile', () {
    final profile = AppUser(
      id: 'u1',
      fullName: 'Amel Ben Salah',
      email: 'amel@esprit.tn',
      createdAt: DateTime(2025, 1, 1),
      skills: const ['Dart'],
    );

    test('fetchProfile returns null when the document does not exist', () async {
      expect(await service.fetchProfile('missing'), isNull);
    });

    test('saveProfile then fetchProfile round-trips and merges', () async {
      await service.saveProfile(profile);
      await service.saveProfile(profile.copyWith(major: 'GL'));

      final loaded = await service.fetchProfile('u1');
      expect(loaded?.fullName, 'Amel Ben Salah');
      expect(loaded?.major, 'GL');
      expect(loaded?.skills, ['Dart']);
    });

    test('watchProfile emits the profile and its later changes', () async {
      final user = await signUp();
      final events = <AppUser?>[];
      final sub = service.watchProfile(user.id).listen(events.add);
      await Future<void>.delayed(Duration.zero);
      await store.update(AppConstants.usersCollection, user.id, {'disabled': true});
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(events.first!.fullName, 'Amel Test');
      expect(events.last!.disabled, isTrue);
    });

    test('watchProfile emits null for a missing document', () async {
      expect(await service.watchProfile('nobody').first, isNull);
    });

    test('updateProfile writes only editable fields; protected ones stay as stored', () async {
      await store.set(AppConstants.usersCollection, 'u1', {
        ...profile.toMap(),
        'role': 'admin',
        'isVerifiedStudent': true,
        'ratingCount': 7,
      });
      final tampered = AppUser(
        id: 'u1',
        fullName: '  amel   ben salah ',
        email: 'hacker@evil.com',
        createdAt: DateTime(2000),
        role: UserRole.recruiter,
        isVerifiedStudent: false,
        ratingCount: 0,
        major: ' GL ',
        skills: const [' Dart ', ''],
      );

      final saved = await service.updateProfile(tampered);
      expect(saved.fullName, 'Amel Ben Salah');
      expect(saved.major, 'GL');
      expect(saved.skills, ['Dart']);

      final stored = userDoc('u1')!;
      expect(stored['fullName'], 'Amel Ben Salah');
      expect(stored['skills'], ['Dart']);
      expect(stored['email'], 'amel@esprit.tn');
      expect(stored['role'], 'admin');
      expect(stored['isVerifiedStudent'], true);
      expect(stored['ratingCount'], 7);
      expect(parseDate(stored['updatedAt']), now);
    });

    test('updateProfile rejects an invalid name without writing', () async {
      await service.saveProfile(profile);
      await expectLater(() => service.updateProfile(profile.copyWith(fullName: 'A')), failsWith('invalid-name'));
      expect(userDoc('u1')!['fullName'], 'Amel Ben Salah');
    });

    test('updateProfile of a missing profile fails', () async {
      await expectLater(() => service.updateProfile(profile), failsWith('unknown'));
    });
  });

  group('changePassword & re-authentication', () {
    test('checks the current password, then replaces it', () async {
      await signUp();
      await service.changePassword(currentPassword: 'secret123', newPassword: 'newpass456');
      await service.signOut();

      await expectLater(() => service.signInWithEmail('amel@esprit.tn', 'secret123'), failsWith('invalid-credential'));
      await service.signInWithEmail('amel@esprit.tn', 'newpass456');
    });

    test('rejects a weak new password', () async {
      await signUp();
      await expectLater(
        () => service.changePassword(currentPassword: 'secret123', newPassword: 'abc'),
        failsWith('weak-password'),
      );
    });

    test('rejects reusing the current password', () async {
      await signUp();
      await expectLater(
        () => service.changePassword(currentPassword: 'secret123', newPassword: 'secret123'),
        failsWith('same-password'),
      );
    });

    test('a wrong current password surfaces as wrong-password and changes nothing', () async {
      await signUp();
      await expectLater(
        () => service.changePassword(currentPassword: 'wrong1234', newPassword: 'newpass456'),
        failsWith('wrong-password'),
      );
      await service.reauthenticateWithPassword('secret123');
    });

    test('re-authentication needs a password', () async {
      await signUp();
      await expectLater(() => service.reauthenticateWithPassword(''), failsWith('password-required'));
    });

    test('without a session → no-session', () async {
      await expectLater(
        () => service.changePassword(currentPassword: 'secret123', newPassword: 'newpass456'),
        failsWith('no-session'),
      );
    });
  });

  group('resetPasswordByAdmin', () {
    test('gives a temporary password that replaces the old one', () async {
      final user = await signUp();
      await service.signOut();

      final temporary = await service.resetPasswordByAdmin(user.id);
      expect(temporary, matches(RegExp(r'^Campus-[a-z]{6}\d{2}$')));

      await expectLater(() => service.signInWithEmail('amel@esprit.tn', 'secret123'), failsWith('invalid-credential'));
      await service.signInWithEmail('amel@esprit.tn', temporary);

      // L'étudiant le change ensuite.
      await service.changePassword(currentPassword: temporary, newPassword: 'newpass456');
      await service.signOut();
      await service.signInWithEmail('amel@esprit.tn', 'newpass456');
    });

    test('each reset gives a different password', () async {
      final user = await signUp();
      final a = await service.resetPasswordByAdmin(user.id);
      final b = await service.resetPasswordByAdmin(user.id);
      expect(a, isNot(b));
    });

    test('an unknown account is reported', () async {
      await expectLater(() => service.resetPasswordByAdmin('nobody'), failsWith('user-not-found'));
    });
  });

  group('phone code (simulated SMS)', () {
    test('requires an active session', () async {
      await expectLater(() => service.sendPhoneOtp('20123456'), failsWith('no-session'));
    });

    test('rejects an invalid number', () async {
      await signUp();
      await expectLater(() => service.sendPhoneOtp('12'), failsWith('invalid-phone-number'));
      expect(service.demoSmsCode, isNull);
    });

    test('verifying before a code was prepared fails with otp-not-sent', () async {
      await signUp();
      await expectLater(() => service.verifyPhoneOtp('123456'), failsWith('otp-not-sent'));
    });

    test('the shown code verifies the number and writes it to the profile', () async {
      final user = await signUp();
      expect(await service.sendPhoneOtp('20 123 456'), '+21620123456');
      final code = service.demoSmsCode!;
      expect(code, matches(RegExp(r'^\d{6}$')));

      await service.verifyPhoneOtp(code);

      final stored = userDoc(user.id)!;
      expect(stored['isPhoneVerified'], true);
      expect(stored['phoneNumber'], '+21620123456');
      expect(service.demoSmsCode, isNull, reason: 'un code ne sert qu\'une fois');
      await expectLater(() => service.verifyPhoneOtp(code), failsWith('otp-not-sent'));
    });

    test('a wrong code is refused and the right one still works', () async {
      final user = await signUp();
      await service.sendPhoneOtp('20123456');
      final code = service.demoSmsCode!;
      final wrong = code == '000000' ? '111111' : '000000';

      await expectLater(() => service.verifyPhoneOtp(wrong), failsWith('invalid-verification-code'));
      await expectLater(() => service.verifyPhoneOtp('12'), failsWith('invalid-verification-code'));
      expect(userDoc(user.id)!['isPhoneVerified'], false);

      await service.verifyPhoneOtp(code);
      expect(userDoc(user.id)!['isPhoneVerified'], true);
    });

    test('the code expires after 5 minutes', () async {
      final user = await signUp();
      await service.sendPhoneOtp('20123456');
      final code = service.demoSmsCode!;

      now = now.add(AuthService.otpValidity + const Duration(seconds: 1));
      await expectLater(() => service.verifyPhoneOtp(code), failsWith('session-expired'));
      expect(userDoc(user.id)!['isPhoneVerified'], false);
      expect(service.demoSmsCode, isNull);
    });

    test('just before expiry the code is still accepted', () async {
      await signUp();
      await service.sendPhoneOtp('20123456');
      final code = service.demoSmsCode!;

      now = now.add(AuthService.otpValidity);
      await service.verifyPhoneOtp(code);
    });

    test('asking again replaces the previous code', () async {
      await signUp();
      await service.sendPhoneOtp('20123456');
      final first = service.demoSmsCode!;
      await service.sendPhoneOtp('20123456');
      final second = service.demoSmsCode!;

      if (first != second) {
        await expectLater(() => service.verifyPhoneOtp(first), failsWith('invalid-verification-code'));
      }
      await service.verifyPhoneOtp(second);
    });

    test('a number verified by another account is refused', () async {
      await signUp(email: 'sami@esprit.tn');
      await service.sendPhoneOtp('20123456');
      await service.verifyPhoneOtp(service.demoSmsCode!);
      await service.signOut();

      await signUp();
      await expectLater(() => service.sendPhoneOtp('20123456'), failsWith('credential-already-in-use'));
      // Son propre numéro peut être revérifié.
      await service.signOut();
      await service.signInWithEmail('sami@esprit.tn', 'secret123');
      await service.sendPhoneOtp('20123456');
    });

    test('the code clears a pending two-factor sign-in', () async {
      await signUpWithTwoFactor();
      await service.signInWithEmail('amel@esprit.tn', 'secret123');
      expect(service.twoFactorPending, isTrue);

      await service.sendPhoneOtp('+21620123456');
      await service.verifyPhoneOtp(service.demoSmsCode!);

      expect(service.twoFactorPending, isFalse);
      expect(service.currentAccount, isNotNull);
    });

    test('signing out forgets the code', () async {
      await signUp();
      await service.sendPhoneOtp('20123456');
      await service.signOut();
      expect(service.demoSmsCode, isNull);
    });
  });

  group('deleteAccount', () {
    test('is a no-op without a session', () async {
      await service.deleteAccount();
    });

    test('requires the password and deletes nothing without it', () async {
      final user = await signUp();
      await expectLater(() => service.deleteAccount(), failsWith('password-required'));
      expect(userDoc(user.id), isNotNull);
      expect(accountDoc(user.id), isNotNull);
    });

    test('a wrong password aborts before anything is deleted', () async {
      final user = await signUp();
      var cleaned = false;
      await expectLater(
        () => service.deleteAccount(password: 'wrong1234', beforeDelete: (_) async => cleaned = true),
        failsWith('wrong-password'),
      );
      expect(cleaned, isFalse);
      expect(userDoc(user.id), isNotNull);
    });

    test('removes the profile, the account and the session; the email is free again', () async {
      final user = await signUp();
      String? cleanedUid;

      await service.deleteAccount(password: 'secret123', beforeDelete: (uid) async => cleanedUid = uid);

      expect(cleanedUid, user.id);
      expect(userDoc(user.id), isNull);
      expect(accountDoc(user.id), isNull);
      expect(service.currentAccount, isNull);
      await expectLater(() => service.signInWithEmail('amel@esprit.tn', 'secret123'), failsWith('invalid-credential'));
      await signUp();
    });

    test('deletes the card photo and the avatar from the phone', () async {
      final user = await signUp();
      await store.update(AppConstants.usersCollection, user.id, {
        'photoUrl': '/data/avatars/${user.id}.jpg',
        'studentCard': {'status': 'pending', 'imagePath': '/data/cards/${user.id}.jpg'},
      });

      await service.deleteAccount(password: 'secret123');

      verify(() => files.delete('/data/cards/${user.id}.jpg')).called(1);
      verify(() => files.delete('/data/avatars/${user.id}.jpg')).called(1);
    });

    test('without files there is nothing to delete', () async {
      await signUp();
      await service.deleteAccount(password: 'secret123');
      verify(() => files.delete(null)).called(2);
    });
  });

  group('exportUserData', () {
    test('bundles account + profile and is JSON-serialisable', () async {
      final user = await signUp();
      final export = await service.exportUserData(user.id);

      final account = export['account'] as Map<String, dynamic>;
      expect(account['uid'], user.id);
      expect(account['email'], 'amel@esprit.tn');
      expect(account['createdAt'], isA<String>());
      expect(account['lastSignInAt'], isA<String>());
      expect(account, isNot(contains('password')));
      final exported = export['profile'] as Map<String, dynamic>;
      expect(exported['fullName'], 'Amel Test');
      expect(exported['createdAt'], isA<String>()); // DateTime → ISO 8601
      expect(() => jsonEncode(export), returnsNormally);
      expect(jsonEncode(export), isNot(contains('salt')));
    });

    test('returns an empty profile for an unknown uid', () async {
      expect((await service.exportUserData('nobody'))['profile'], isEmpty);
    });
  });

  group('biometrics', () {
    test('returns false when the device cannot check biometrics', () async {
      final local = MockLocalAuth();
      when(() => local.canCheckBiometrics).thenAnswer((_) async => false);
      when(() => local.isDeviceSupported()).thenAnswer((_) async => true);
      final s = build(localAuth: () => local);

      expect(await s.authenticateWithBiometrics(), isFalse);
      verifyNever(() => local.authenticate(
            localizedReason: any(named: 'localizedReason'),
            options: any(named: 'options'),
          ));
    });

    test('returns the platform answer when supported', () async {
      final local = MockLocalAuth();
      when(() => local.canCheckBiometrics).thenAnswer((_) async => true);
      when(() => local.isDeviceSupported()).thenAnswer((_) async => true);
      when(() => local.authenticate(
            localizedReason: any(named: 'localizedReason'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => true);
      final s = build(localAuth: () => local);

      expect(await s.authenticateWithBiometrics(), isTrue);
    });

    test('canUseBiometrics requires support, a sensor and an enrolled biometric', () async {
      final local = MockLocalAuth();
      when(() => local.isDeviceSupported()).thenAnswer((_) async => true);
      when(() => local.canCheckBiometrics).thenAnswer((_) async => true);
      when(() => local.getAvailableBiometrics()).thenAnswer((_) async => [BiometricType.fingerprint]);
      final s = build(localAuth: () => local);
      expect(await s.canUseBiometrics(), isTrue);

      when(() => local.getAvailableBiometrics()).thenAnswer((_) async => []);
      expect(await s.canUseBiometrics(), isFalse);

      when(() => local.isDeviceSupported()).thenAnswer((_) async => false);
      expect(await s.canUseBiometrics(), isFalse);
    });

    test('canUseBiometrics never throws', () async {
      final local = MockLocalAuth();
      when(() => local.isDeviceSupported()).thenThrow(Exception('no plugin'));
      final s = build(localAuth: () => local);
      expect(await s.canUseBiometrics(), isFalse);
    });

    test('the local_auth plugin is only created when needed', () async {
      var created = 0;
      final s = build(localAuth: () {
        created++;
        return MockLocalAuth();
      });
      await s.registerWithEmail(email: 'amel@esprit.tn', password: 'secret123', fullName: 'Amel Test');
      await s.signOut();
      expect(created, 0);
    });
  });
}
