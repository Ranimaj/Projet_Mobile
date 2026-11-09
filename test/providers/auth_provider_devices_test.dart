import 'dart:async';

import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/services/auth_service.dart';
import 'package:campusconnect/services/device_session_service.dart';
import 'package:campusconnect/services/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/local_db.dart';
import '../helpers/mocks.dart';

/// Historique des connexions et double authentification, vus depuis
/// l'AuthProvider (AuthService mocké, historique réel sur SQLite en mémoire).
void main() {
  late MockAuthService service;
  late StreamController<AuthAccount?> authStream;
  late DeviceSessionService sessions;
  final providers = <AuthProvider>[];

  const account = AuthAccount(uid: 'uid-1', email: 'amel@esprit.tn');
  final user = AppUser(
    id: 'uid-1',
    fullName: 'Amel Ben Salah',
    email: 'amel@esprit.tn',
    createdAt: DateTime(2025, 1, 1),
    isPhoneVerified: true,
    phoneNumber: '+21698765432',
  );

  AuthProvider app() {
    final p = AuthProvider(authService: service, deviceSessionService: sessions);
    providers.add(p);
    return p;
  }

  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Connexion par mot de passe ; [twoFactor] : la session s'ouvre en
  /// attente du code.
  Future<AuthProvider> login({bool twoFactor = false}) async {
    when(() => service.twoFactorPending).thenReturn(twoFactor);
    when(() => service.signInWithEmail(any(), any())).thenAnswer((_) async {
      authStream.add(account);
      return account;
    });
    final p = app();
    expect(await p.login('amel@esprit.tn', 'Secret123!'), isTrue);
    await settle();
    return p;
  }

  setUpAll(() => registerFallbackValue(user));

  setUp(() async {
    await openTestDatabase();
    sessions = DeviceSessionService(
      store: LocalStore(),
      deviceInfo: () async => (name: 'Pixel 8', platform: 'android'),
      city: () async => null,
    );
    service = MockAuthService();
    authStream = StreamController<AuthAccount?>.broadcast();
    when(() => service.authStateChanges).thenAnswer((_) => authStream.stream);
    when(() => service.watchProfile(any())).thenAnswer((_) => const Stream<AppUser?>.empty().asBroadcastStream());
    when(() => service.fetchProfile('uid-1')).thenAnswer((_) async => user);
    when(() => service.twoFactorPending).thenReturn(false);
    when(() => service.signOut()).thenAnswer((_) async {});
  });

  tearDown(() async {
    for (final p in providers) {
      p.dispose();
    }
    providers.clear();
    await authStream.close();
    await closeTestDatabase();
  });

  test('a password login opens the app and is added to the history', () async {
    final p = await login();
    expect(p.status, AuthStatus.authenticated);
    expect(p.twoFactorRequired, isFalse);
    expect(await sessions.watchLogins('uid-1').first, hasLength(1));
  });

  test('a restored session (app restart) is not a new login', () async {
    final p = app();
    authStream.add(account);
    await settle();
    expect(p.status, AuthStatus.authenticated);
    expect(await sessions.watchLogins('uid-1').first, isEmpty);
  });

  test('with 2FA the login waits for the SMS code, then opens the app', () async {
    final p = await login(twoFactor: true);
    expect(p.status, AuthStatus.authenticated);
    expect(p.twoFactorRequired, isTrue);
    // Le mot de passe était bon : la connexion figure déjà dans l'historique.
    expect(await sessions.watchLogins('uid-1').first, hasLength(1));

    when(() => service.verifyPhoneOtp('123456')).thenAnswer((_) async {});
    expect(await p.verifyPhoneOtp('123456'), isTrue);
    expect(p.twoFactorRequired, isFalse);
  });

  test('a wrong 2FA code keeps the app locked', () async {
    final p = await login(twoFactor: true);
    when(() => service.verifyPhoneOtp(any())).thenThrow(Exception('invalid-verification-code'));
    expect(await p.verifyPhoneOtp('000000'), isFalse);
    expect(p.twoFactorRequired, isTrue);
  });

  test('cancelling the 2FA step logs out', () async {
    final p = await login(twoFactor: true);
    expect(await p.logout(), isTrue);
    expect(p.status, AuthStatus.visitor);
    expect(p.twoFactorRequired, isFalse);
  });

  test('logout marks this phone as signed out', () async {
    final p = await login();
    expect(await p.logout(), isTrue);
    verify(() => service.signOut()).called(1);
    expect((await sessions.watchThisDevice('uid-1').first)!.signedOut, isTrue);
  });

  test('the GDPR export includes this phone and the logins', () async {
    when(() => service.exportUserData('uid-1')).thenAnswer((_) async => {'profile': <String, dynamic>{}});
    final p = await login();
    final data = await p.exportMyData();
    expect((data['devices'] as List).single['name'], 'Pixel 8');
    expect(data['logins'], hasLength(1));
    expect(data, contains('profile'));
  });

  test('deleting the account erases the login history', () async {
    when(() => service.deleteAccount(password: any(named: 'password'), beforeDelete: any(named: 'beforeDelete')))
        .thenAnswer((inv) async {
      final before = inv.namedArguments[#beforeDelete] as Future<void> Function(String)?;
      await before?.call('uid-1');
    });
    final p = await login();
    expect(await p.deleteAccount(password: 'Secret123!'), isTrue);
    expect(await sessions.watchLogins('uid-1').first, isEmpty);
    expect(await sessions.watchThisDevice('uid-1').first, isNull);
  });
}
