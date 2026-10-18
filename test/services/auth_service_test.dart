import 'dart:convert';

import 'package:campusconnect/core/constants/app_constants.dart';
import 'package:campusconnect/core/utils/auth_failure.dart';
import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/services/auth_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

class MockLocalAuth extends Mock implements LocalAuthentication {}

class MockGoogleSignIn extends Mock implements GoogleSignIn {}

class MockUserCredential extends Mock implements UserCredential {}

class MockAuthInstance extends Mock implements FirebaseAuth {}

class MockFbUser extends Mock implements User {}

void main() {
  late MockFirebaseAuth auth;
  late FakeFirebaseFirestore firestore;
  late AuthService service;

  setUpAll(() => registerFallbackValue(const AuthenticationOptions()));

  setUp(() {
    auth = MockFirebaseAuth();
    firestore = FakeFirebaseFirestore();
    service = AuthService(auth: auth, firestore: firestore);
  });

  Future<Map<String, dynamic>?> userDoc(String uid) async =>
      (await firestore.collection(AppConstants.usersCollection).doc(uid).get()).data();

  final profile = AppUser(
    id: 'u1',
    fullName: 'Amel Ben Salah',
    email: 'amel@esprit.tn',
    createdAt: DateTime(2025, 1, 1),
    skills: const ['Dart'],
  );

  Future<AppUser> signUp() =>
      service.registerWithEmail(email: 'a@b.co', password: 'secret123', fullName: 'Amel Test');

  group('registerWithEmail', () {
    test('creates the account and a normalized Firestore profile', () async {
      final user = await service.registerWithEmail(
        email: '  Amel.BenSalah@Esprit.TN ',
        password: 'secret123',
        fullName: '  amel   ben salah ',
      );

      expect(user.email, 'amel.bensalah@esprit.tn');
      expect(user.fullName, 'Amel Ben Salah');
      expect(auth.currentUser?.email, 'amel.bensalah@esprit.tn');

      final stored = await userDoc(user.id);
      expect(stored, isNotNull);
      expect(stored!['fullName'], 'Amel Ben Salah');
      expect(stored['role'], 'student');
      expect(stored['isPhoneVerified'], false);
    });

    test('translates email-already-in-use into an AuthFailure', () async {
      whenCalling(Invocation.method(#createUserWithEmailAndPassword, null))
          .on(auth)
          .thenThrow(FirebaseAuthException(code: 'email-already-in-use'));

      expect(
        () => service.registerWithEmail(email: 'a@b.co', password: 'secret123', fullName: 'Amel Test'),
        throwsA(isA<AuthFailure>().having((f) => f.code, 'code', 'email-already-in-use')),
      );
      expect(firestore.dump(), isNot(contains('Amel Test')));
    });
  });

  group('signInWithEmail', () {
    test('signs in and sends a trimmed, lowercased email (password untouched)', () async {
      final mockAuth = MockAuthInstance();
      when(() => mockAuth.signInWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenAnswer((_) async => MockUserCredential());
      final s = AuthService(auth: mockAuth, firestore: firestore);

      await s.signInWithEmail('  USER@Esprit.tn ', ' Secret123 ');
      verify(() => mockAuth.signInWithEmailAndPassword(
            email: 'user@esprit.tn',
            password: ' Secret123 ',
          )).called(1);
    });

    test('signs in against the auth backend', () async {
      await service.signInWithEmail('a@b.co', 'secret123');
      expect(auth.currentUser, isNotNull);
    });

    test('maps wrong credentials to a friendly failure', () async {
      whenCalling(Invocation.method(#signInWithEmailAndPassword, null))
          .on(auth)
          .thenThrow(FirebaseAuthException(code: 'invalid-credential'));

      expect(
        () => service.signInWithEmail('a@b.co', 'bad'),
        throwsA(isA<AuthFailure>().having((f) => f.message, 'message', 'Email ou mot de passe incorrect.')),
      );
    });
  });

  group('password reset', () {
    test('succeeds for a valid email', () async {
      await service.sendPasswordReset(' User@Esprit.tn ');
    });

    test('surfaces user-not-found as an AuthFailure', () async {
      whenCalling(Invocation.method(#sendPasswordResetEmail, null))
          .on(auth)
          .thenThrow(FirebaseAuthException(code: 'user-not-found'));

      expect(
        () => service.sendPasswordReset('ghost@esprit.tn'),
        throwsA(isA<AuthFailure>().having((f) => f.code, 'code', 'user-not-found')),
      );
    });
  });

  group('profile', () {

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

    test('exportUserData bundles account + profile and is JSON-serialisable', () async {
      final user = await signUp();
      final export = await service.exportUserData(user.id);

      final account = export['account'] as Map<String, dynamic>;
      expect(account['email'], 'a@b.co');
      expect(account['providers'], contains('password'));
      final exported = export['profile'] as Map<String, dynamic>;
      expect(exported['fullName'], 'Amel Test');
      expect(exported['createdAt'], isA<String>()); // Timestamp → ISO 8601
      expect(() => jsonEncode(export), returnsNormally);
    });

    test('exportUserData returns an empty profile for an unknown uid', () async {
      expect((await service.exportUserData('nobody'))['profile'], isEmpty);
    });
  });

  group('deleteAccount', () {
    test('is a no-op without a session', () async {
      await service.deleteAccount();
    });

    test('requires the password for an email/password account and deletes nothing', () async {
      final user = await signUp();
      await expectLater(
        () => service.deleteAccount(),
        throwsA(isA<AuthFailure>().having((f) => f.code, 'code', 'password-required')),
      );
      expect(await userDoc(user.id), isNotNull);
    });

    test('re-authenticates, then removes the profile and the account', () async {
      final user = await signUp();
      await service.deleteAccount(password: 'secret123');
      expect(await userDoc(user.id), isNull);
    });

    test('a wrong password aborts before anything is deleted', () async {
      final user = await signUp();
      whenCalling(Invocation.method(#reauthenticateWithCredential, null))
          .on(auth.currentUser!)
          .thenThrow(FirebaseAuthException(code: 'wrong-password'));

      await expectLater(
        () => service.deleteAccount(password: 'bad'),
        throwsA(isA<AuthFailure>().having((f) => f.code, 'code', 'wrong-password')),
      );
      expect(await userDoc(user.id), isNotNull);
    });

    test('restores the profile when the account deletion itself fails', () async {
      final user = await signUp();
      whenCalling(Invocation.method(#delete, null))
          .on(auth.currentUser!)
          .thenThrow(FirebaseAuthException(code: 'requires-recent-login'));

      await expectLater(
        () => service.deleteAccount(password: 'secret123'),
        throwsA(isA<AuthFailure>().having((f) => f.code, 'code', 'requires-recent-login')),
      );
      final restored = await userDoc(user.id);
      expect(restored, isNotNull);
      expect(restored!['fullName'], 'Amel Test');
    });
  });

  group('updateProfile', () {
    test('writes only editable fields; protected ones stay as stored', () async {
      await firestore.collection(AppConstants.usersCollection).doc('u1').set({
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

      final stored = await userDoc('u1');
      expect(stored!['fullName'], 'Amel Ben Salah');
      expect(stored['skills'], ['Dart']);
      expect(stored['email'], 'amel@esprit.tn');
      expect(stored['role'], 'admin');
      expect(stored['isVerifiedStudent'], true);
      expect(stored['ratingCount'], 7);
      expect(stored['updatedAt'], isNotNull);
    });

    test('rejects an invalid name without writing', () async {
      await service.saveProfile(profile);
      await expectLater(
        () => service.updateProfile(profile.copyWith(fullName: 'A')),
        throwsA(isA<AuthFailure>().having((f) => f.code, 'code', 'invalid-name')),
      );
      expect((await userDoc('u1'))!['fullName'], 'Amel Ben Salah');
    });

    test('syncs display name and photo to Firebase Auth for the current user', () async {
      final user = await signUp();
      await service.updateProfile(user.copyWith(fullName: 'amel nouvelle', photoUrl: 'https://x/y.jpg'));
      expect(auth.currentUser!.displayName, 'Amel Nouvelle');
      expect(auth.currentUser!.photoURL, 'https://x/y.jpg');
    });
  });

  group('changePassword & re-authentication', () {
    test('re-authenticates with the current password, then updates it', () async {
      await signUp();
      await service.changePassword(currentPassword: 'secret123', newPassword: 'nouveau456');
    });

    test('rejects a weak new password', () async {
      await signUp();
      expect(
        () => service.changePassword(currentPassword: 'secret123', newPassword: 'short'),
        throwsA(isA<AuthFailure>().having((f) => f.code, 'code', 'weak-password')),
      );
    });

    test('rejects reusing the current password', () async {
      await signUp();
      expect(
        () => service.changePassword(currentPassword: 'secret123', newPassword: 'secret123'),
        throwsA(isA<AuthFailure>().having((f) => f.code, 'code', 'same-password')),
      );
    });

    test('a wrong current password surfaces as wrong-password', () async {
      await signUp();
      whenCalling(Invocation.method(#reauthenticateWithCredential, null))
          .on(auth.currentUser!)
          .thenThrow(FirebaseAuthException(code: 'wrong-password'));
      expect(
        () => service.changePassword(currentPassword: 'bad', newPassword: 'nouveau456'),
        throwsA(isA<AuthFailure>().having((f) => f.code, 'code', 'wrong-password')),
      );
    });

    test('Google-only accounts have no password to change', () async {
      final googleAuth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'g1', email: 'g@gmail.com', providerData: [FakeUserInfo('google.com')]),
      );
      final s = AuthService(auth: googleAuth, firestore: firestore);
      expect(s.hasPasswordProvider, isFalse);
      expect(s.providerIds, ['google.com']);
      expect(
        () => s.changePassword(currentPassword: 'x', newPassword: 'nouveau456'),
        throwsA(isA<AuthFailure>().having((f) => f.code, 'code', 'no-password-provider')),
      );
    });

    test('without a session → no-session', () {
      expect(
        () => service.reauthenticateWithPassword('secret123'),
        throwsA(isA<AuthFailure>().having((f) => f.code, 'code', 'no-session')),
      );
    });
  });

  group('reloadUser', () {
    test('returns false without a session', () async {
      expect(await service.reloadUser(), isFalse);
    });

    test('returns the verification status of the reloaded user', () async {
      final verifiedAuth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'v1', email: 'v@esprit.tn', isEmailVerified: true),
      );
      expect(await AuthService(auth: verifiedAuth, firestore: firestore).reloadUser(), isTrue);

      final unverifiedAuth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'n1', email: 'n@esprit.tn', isEmailVerified: false),
      );
      expect(await AuthService(auth: unverifiedAuth, firestore: firestore).reloadUser(), isFalse);
    });
  });

  group('phone OTP', () {
    test('requires an active session', () async {
      expect(
        () => service.sendPhoneOtp('20123456'),
        throwsA(isA<AuthFailure>().having((f) => f.code, 'code', 'no-session')),
      );
    });

    test('rejects an invalid number before calling Firebase', () async {
      await service.registerWithEmail(email: 'a@b.co', password: 'secret123', fullName: 'Amel Test');
      expect(
        () => service.sendPhoneOtp('abc'),
        throwsA(isA<AuthFailure>().having((f) => f.code, 'code', 'invalid-phone-number')),
      );
    });

    test('verifying before a code was sent fails with otp-not-sent', () {
      expect(
        () => service.verifyPhoneOtp('123456'),
        throwsA(isA<AuthFailure>().having((f) => f.code, 'code', 'otp-not-sent')),
      );
    });

    /// Session mocktail dont `verifyPhoneNumber` répond aussitôt « code envoyé ».
    (MockAuthInstance, MockFbUser) phoneSession(List<String> providers) {
      final fbAuth = MockAuthInstance();
      final user = MockFbUser();
      when(() => fbAuth.currentUser).thenReturn(user);
      when(() => user.uid).thenReturn('u-phone');
      when(() => user.providerData).thenReturn([for (final p in providers) FakeUserInfo(p)]);
      when(() => user.updatePhoneNumber(any())).thenAnswer((_) async {});
      when(() => user.linkWithCredential(any())).thenAnswer((_) async => MockUserCredential());
      when(() => fbAuth.verifyPhoneNumber(
            phoneNumber: any(named: 'phoneNumber'),
            forceResendingToken: any(named: 'forceResendingToken'),
            timeout: any(named: 'timeout'),
            verificationCompleted: any(named: 'verificationCompleted'),
            verificationFailed: any(named: 'verificationFailed'),
            codeSent: any(named: 'codeSent'),
            codeAutoRetrievalTimeout: any(named: 'codeAutoRetrievalTimeout'),
          )).thenAnswer((inv) async {
        final codeSent = inv.namedArguments[#codeSent] as PhoneCodeSent;
        codeSent('verif-1', 7);
      });
      return (fbAuth, user);
    }

    setUpAll(() {
      registerFallbackValue(Duration.zero);
      registerFallbackValue(PhoneAuthProvider.credential(verificationId: 'f', smsCode: '000000'));
      registerFallbackValue((PhoneAuthCredential c) {});
      registerFallbackValue((FirebaseAuthException e) {});
      registerFallbackValue((String id, int? token) {});
      registerFallbackValue((String id) {});
    });

    test('a first number is linked to the account and written to the profile', () async {
      final (fbAuth, user) = phoneSession(['password']);
      final s = AuthService(auth: fbAuth, firestore: firestore);

      expect(await s.sendPhoneOtp('92 755 660'), '+21692755660');
      await s.verifyPhoneOtp('261983');

      verify(() => user.linkWithCredential(any())).called(1);
      verifyNever(() => user.updatePhoneNumber(any()));
      final doc = await firestore.collection('users').doc('u-phone').get();
      expect(doc.data()!['phoneNumber'], '+21692755660');
      expect(doc.data()!['isPhoneVerified'], isTrue);
    });

    test('changing the number of an account that already has one uses updatePhoneNumber', () async {
      // Firebase refuse un second `link` du fournisseur téléphone
      // (provider-already-linked) : on met le numéro à jour à la place.
      final (fbAuth, user) = phoneSession(['password', 'phone']);
      final s = AuthService(auth: fbAuth, firestore: firestore);

      await s.sendPhoneOtp('92755661');
      await s.verifyPhoneOtp('123456');

      verify(() => user.updatePhoneNumber(any())).called(1);
      verifyNever(() => user.linkWithCredential(any()));
      final doc = await firestore.collection('users').doc('u-phone').get();
      expect(doc.data()!['phoneNumber'], '+21692755661');
    });

    test('a number already used by another account is reported as such', () async {
      final (fbAuth, user) = phoneSession(['password']);
      when(() => user.linkWithCredential(any()))
          .thenThrow(FirebaseAuthException(code: 'credential-already-in-use'));
      final s = AuthService(auth: fbAuth, firestore: firestore);
      await s.sendPhoneOtp('92755662');

      expect(
        () => s.verifyPhoneOtp('123456'),
        throwsA(isA<AuthFailure>().having((f) => f.message, 'message', contains('déjà associé à un autre compte'))),
      );
    });
  });

  group('biometrics', () {
    test('returns false when the device cannot check biometrics', () async {
      final local = MockLocalAuth();
      when(() => local.canCheckBiometrics).thenAnswer((_) async => false);
      when(() => local.isDeviceSupported()).thenAnswer((_) async => true);
      final s = AuthService(auth: auth, firestore: firestore, localAuthFactory: () => local);

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
      final s = AuthService(auth: auth, firestore: firestore, localAuthFactory: () => local);

      expect(await s.authenticateWithBiometrics(), isTrue);
    });

    test('canUseBiometrics requires support, a sensor and an enrolled biometric', () async {
      final local = MockLocalAuth();
      when(() => local.isDeviceSupported()).thenAnswer((_) async => true);
      when(() => local.canCheckBiometrics).thenAnswer((_) async => true);
      when(() => local.getAvailableBiometrics()).thenAnswer((_) async => [BiometricType.fingerprint]);
      final s = AuthService(auth: auth, firestore: firestore, localAuthFactory: () => local);
      expect(await s.canUseBiometrics(), isTrue);

      when(() => local.getAvailableBiometrics()).thenAnswer((_) async => []);
      expect(await s.canUseBiometrics(), isFalse);

      when(() => local.isDeviceSupported()).thenAnswer((_) async => false);
      expect(await s.canUseBiometrics(), isFalse);
    });

    test('canUseBiometrics never throws', () async {
      final local = MockLocalAuth();
      when(() => local.isDeviceSupported()).thenThrow(Exception('no plugin'));
      final s = AuthService(auth: auth, firestore: firestore, localAuthFactory: () => local);
      expect(await s.canUseBiometrics(), isFalse);
    });
  });

  group('Google Sign-In laziness', () {
    test('is not constructed by construction, sign-out or email sign-in', () async {
      var built = 0;
      final s = AuthService(
        auth: auth,
        firestore: firestore,
        googleFactory: () {
          built++;
          return MockGoogleSignIn();
        },
      );
      await s.signInWithEmail('a@b.co', 'secret123');
      await s.signOut();
      expect(built, 0);
    });

    test('a cancelled Google flow returns null without touching Firebase', () async {
      final google = MockGoogleSignIn();
      when(() => google.signIn()).thenAnswer((_) async => null);
      final s = AuthService(auth: auth, firestore: firestore, googleFactory: () => google);

      expect(await s.signInWithGoogle(), isNull);
      expect(auth.currentUser, isNull);
    });

    test('sign-out also signs out of Google once it was used', () async {
      final google = MockGoogleSignIn();
      when(() => google.signIn()).thenAnswer((_) async => null);
      when(() => google.signOut()).thenAnswer((_) async => null);
      final s = AuthService(auth: auth, firestore: firestore, googleFactory: () => google);

      await s.signInWithGoogle();
      await s.signOut();
      verify(() => google.signOut()).called(1);
    });
  });

  test('signOut clears the current user', () async {
    await service.signInWithEmail('a@b.co', 'secret123');
    expect(service.currentFirebaseUser, isNotNull);
    await service.signOut();
    expect(service.currentFirebaseUser, isNull);
  });
}
