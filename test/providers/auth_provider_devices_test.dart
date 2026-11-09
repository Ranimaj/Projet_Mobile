import 'dart:async';

import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/services/device_session_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/mocks.dart';

/// Connexion, appareils de confiance et fermeture à distance, vus depuis
/// l'AuthProvider (Firestore factice, un « téléphone » par service).
void main() {
  late MockAuthService service;
  late StreamController<User?> authStream;
  late FakeFirebaseFirestore db;
  final providers = <AuthProvider>[];

  final user = AppUser(
    id: 'uid-1',
    fullName: 'Amel Ben Salah',
    email: 'amel@esprit.tn',
    createdAt: DateTime(2025, 1, 1),
    isPhoneVerified: true,
    phoneNumber: '+21698765432',
  );

  DeviceSessionService phone(String name) {
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPreferences.getInstance();
    return DeviceSessionService(
      firestore: db,
      deviceInfo: () async => (name: name, platform: 'android'),
      city: () async => null,
      prefs: () => prefs,
    );
  }

  AuthProvider app(DeviceSessionService sessions) {
    final p = AuthProvider(authService: service, deviceSessionService: sessions);
    providers.add(p);
    return p;
  }

  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUpAll(() => registerFallbackValue(user));

  setUp(() {
    db = FakeFirebaseFirestore();
    service = MockAuthService();
    authStream = StreamController<User?>.broadcast();
    when(() => service.authStateChanges).thenAnswer((_) => authStream.stream);
    when(() => service.watchProfile(any()))
        .thenAnswer((_) => const Stream<AppUser?>.empty().asBroadcastStream());
    when(() => service.signOut()).thenAnswer((_) async {});
  });

  tearDown(() async {
    for (final p in providers) {
      p.dispose();
    }
    providers.clear();
    await authStream.close();
  });

  test('without 2FA a new device opens the app directly', () async {
    when(() => service.fetchProfile('uid-1')).thenAnswer((_) async => user);
    final p = app(phone('Pixel 8'));
    authStream.add(MockUser(uid: 'uid-1'));
    await settle();
    expect(p.status, AuthStatus.authenticated);
    expect(p.deviceConfirmationRequired, isFalse);
    expect((await db.collection('users/uid-1/logins').get()).docs, hasLength(1));
  });

  test('with 2FA a new device waits for the SMS code, which then trusts it', () async {
    final twoFactor = user.copyWith(twoFactorEnabled: true);
    when(() => service.fetchProfile('uid-1')).thenAnswer((_) async => twoFactor);
    await phone('Pixel 8').onSignedIn('uid-1', twoFactor: true); // appareil habituel

    final p = app(phone('iPhone 15'));
    authStream.add(MockUser(uid: 'uid-1'));
    await settle();
    expect(p.status, AuthStatus.authenticated);
    expect(p.deviceConfirmationRequired, isTrue);

    when(() => service.verifyPhoneOtp('123456')).thenAnswer((_) async {});
    expect(await p.verifyPhoneOtp('123456'), isTrue);
    expect(p.deviceConfirmationRequired, isFalse);
    final devices = await p.deviceSessions!.watchDevices('uid-1').first;
    expect(devices.firstWhere((d) => d.name == 'iPhone 15').trusted, isTrue);
  });

  test('2FA is ignored without a verified phone (no SMS possible)', () async {
    when(() => service.fetchProfile('uid-1'))
        .thenAnswer((_) async => AppUser(
              id: 'uid-1',
              fullName: 'Amel',
              email: 'amel@esprit.tn',
              createdAt: DateTime(2025, 1, 1),
              twoFactorEnabled: true,
            ));
    await phone('Pixel 8').onSignedIn('uid-1', twoFactor: false);
    final p = app(phone('iPhone 15'));
    authStream.add(MockUser(uid: 'uid-1'));
    await settle();
    expect(p.deviceConfirmationRequired, isFalse);
  });

  test('approval from another device lets the pending one in', () async {
    final twoFactor = user.copyWith(twoFactorEnabled: true);
    when(() => service.fetchProfile('uid-1')).thenAnswer((_) async => twoFactor);
    final pixel = phone('Pixel 8');
    await pixel.onSignedIn('uid-1', twoFactor: true);

    final iphone = phone('iPhone 15');
    final p = app(iphone);
    authStream.add(MockUser(uid: 'uid-1'));
    await settle();
    expect(p.deviceConfirmationRequired, isTrue);

    await pixel.setTrusted('uid-1', (await iphone.currentDevice()).id, true);
    await settle();
    expect(p.deviceConfirmationRequired, isFalse);
  });

  test('a session closed from another device signs this one out', () async {
    when(() => service.fetchProfile('uid-1')).thenAnswer((_) async => user);
    final pixel = phone('Pixel 8');
    await pixel.onSignedIn('uid-1', twoFactor: false);
    final iphone = phone('iPhone 15');
    final p = app(iphone);
    authStream.add(MockUser(uid: 'uid-1'));
    await settle();
    expect(p.status, AuthStatus.authenticated);

    await pixel.revoke('uid-1', (await iphone.currentDevice()).id);
    await settle();
    verify(() => service.signOut()).called(1);
    expect(p.status, AuthStatus.visitor);
    expect(p.errorCode, AuthProvider.sessionRevokedCode);
    expect(p.errorMessage, 'Ta session a été fermée depuis un autre appareil.');
  });

  test('logout marks this device as signed out', () async {
    when(() => service.fetchProfile('uid-1')).thenAnswer((_) async => user);
    final pixel = phone('Pixel 8');
    final p = app(pixel);
    authStream.add(MockUser(uid: 'uid-1'));
    await settle();
    expect(await p.logout(), isTrue);
    expect((await pixel.watchThisDevice('uid-1').first)!.signedOut, isTrue);
  });

  test('the GDPR export includes devices and logins', () async {
    when(() => service.fetchProfile('uid-1')).thenAnswer((_) async => user);
    when(() => service.exportUserData('uid-1')).thenAnswer((_) async => {'profile': <String, dynamic>{}});
    final p = app(phone('Pixel 8'));
    authStream.add(MockUser(uid: 'uid-1'));
    await settle();
    final data = await p.exportMyData();
    expect((data['devices'] as List).single['name'], 'Pixel 8');
    expect(data['logins'], hasLength(1));
    expect(data, contains('profile'));
  });
}
