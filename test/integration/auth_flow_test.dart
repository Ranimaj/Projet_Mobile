import 'package:campusconnect/core/constants/app_constants.dart';
import 'package:campusconnect/core/theme/app_theme.dart';
import 'package:campusconnect/core/utils/local_database.dart';
import 'package:campusconnect/core/utils/password_hasher.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/screens/auth/forgot_password_screen.dart';
import 'package:campusconnect/screens/auth/login_screen.dart';
import 'package:campusconnect/screens/auth/otp_verification_screen.dart';
import 'package:campusconnect/screens/auth/register_screen.dart';
import 'package:campusconnect/services/auth_service.dart';
import 'package:campusconnect/services/device_session_service.dart';
import 'package:campusconnect/services/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/local_db.dart';
import '../helpers/mocks.dart';
import '../helpers/pump_app.dart';

/// Parcours complets écran → provider → service → SQLite (en mémoire), avec
/// le même routage que `RootRouter` dans main.dart.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      body: Center(
        child: switch (auth.status) {
          AuthStatus.unknown => const CircularProgressIndicator(),
          AuthStatus.authenticated when auth.twoFactorRequired => const Text('2FA'),
          AuthStatus.authenticated => Text('HOME:${auth.currentUser?.fullName ?? '?'}'),
          AuthStatus.visitor => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('VISITOR'),
                ElevatedButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => LoginScreen(prefs: FakeLoginPrefs()))),
                  child: const Text('go-login'),
                ),
                ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen())),
                  child: const Text('go-register'),
                ),
              ],
            ),
        },
      ),
    );
  }
}

/// Base SQLite en mémoire dans l'isolat du test : ses Futures se terminent
/// dans le temps simulé de testWidgets (pas de vraie E/S à attendre).
Future<void> openInlineTestDatabase() {
  sqfliteFfiInit();
  return LocalDatabase.open(factory: databaseFactoryFfiNoIsolate, path: inMemoryDatabasePath);
}

void main() {
  late LocalStore store;
  late AuthService service;
  late AuthProvider provider;

  /// Comme `testWidgets`, mais ferme la base à la fin du test lui-même : ses
  /// Futures appartiennent au temps simulé, un `tearDown` ne les verrait pas
  /// se terminer.
  void flowTest(String description, Future<void> Function(WidgetTester tester) body) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        provider.dispose();
        await closeTestDatabase();
      }
    });
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pumpAndSettle();
  }

  /// Crée un compte directement dans la base (sans session ouverte).
  Future<String> seedAccount(
    WidgetTester tester, {
    String email = 'amel@esprit.tn',
    String fullName = 'Amel Ben Salah',
    Map<String, dynamic> profile = const {},
  }) async {
    final user = await service.registerWithEmail(email: email, password: 'secret123', fullName: fullName);
    if (profile.isNotEmpty) await store.update(AppConstants.usersCollection, user.id, profile);
    await service.signOut();
    return user.id;
  }

  Future<void> start(WidgetTester tester, {Future<void> Function()? before}) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await openInlineTestDatabase();
    store = LocalStore();
    service = AuthService(store: store, storage: MockStorageService(), hasher: PasswordHasher(iterations: 1));
    await before?.call();
    provider = AuthProvider(
      authService: service,
      deviceSessionService: DeviceSessionService(
        store: store,
        deviceInfo: () async => (name: 'Pixel test', platform: 'android'),
        city: () async => null,
      ),
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: provider,
        child: MaterialApp(theme: AppTheme.light, home: const _Root()),
      ),
    );
    await settle(tester);
  }

  Future<void> login(WidgetTester tester, String email, String password) async {
    await tester.tap(find.text('go-login'));
    await tester.pumpAndSettle();
    await enterField(tester, 0, email);
    await enterField(tester, 1, password);
    await tapText(tester, 'Se connecter');
    await settle(tester);
  }

  flowTest('a signed-out user lands on the visitor page', (tester) async {
    await start(tester);
    expect(find.text('VISITOR'), findsOneWidget);
    expect(provider.status, AuthStatus.visitor);
  });

  flowTest('register → account + profile stored (normalized) → home with the new name', (tester) async {
    await start(tester);

    await tester.tap(find.text('go-register'));
    await tester.pumpAndSettle();

    await enterField(tester, 0, '  amel   ben salah ');
    await enterField(tester, 1, ' Amel.BenSalah@Esprit.TN ');
    await enterField(tester, 3, 'secret123');
    await enterField(tester, 4, 'secret123');
    await tapText(tester, 'Créer mon compte');
    await settle(tester);

    expect(find.byType(RegisterScreen), findsNothing);
    expect(find.text('HOME:Amel Ben Salah'), findsOneWidget);

    final uid = service.currentAccount!.uid;
    final stored = store.get(AppConstants.usersCollection, uid);
    expect(stored?['email'], 'amel.bensalah@esprit.tn');
    expect(stored?['fullName'], 'Amel Ben Salah');
    expect(stored?['role'], 'student');
    expect(store.get(AuthService.accountsCollection, uid)?['email'], 'amel.bensalah@esprit.tn');
  });

  flowTest('register with a phone → the simulated SMS code verifies it', (tester) async {
    await start(tester);

    await tester.tap(find.text('go-register'));
    await tester.pumpAndSettle();
    await enterField(tester, 0, 'Amel Ben Salah');
    await enterField(tester, 1, 'amel@esprit.tn');
    await enterField(tester, 2, '20 123 456');
    await enterField(tester, 3, 'secret123');
    await enterField(tester, 4, 'secret123');
    await tapText(tester, 'Créer mon compte');
    await settle(tester);

    expect(find.byType(OtpVerificationScreen), findsOneWidget);
    final code = service.demoSmsCode!;
    expect(find.text('SMS simulé : ton code est $code'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('otp-field')), code);
    await settle(tester);

    expect(find.byType(OtpVerificationScreen), findsNothing);
    final stored = store.get(AppConstants.usersCollection, service.currentAccount!.uid)!;
    expect(stored['isPhoneVerified'], true);
    expect(stored['phoneNumber'], '+21620123456');
  });

  flowTest('login with an existing account loads its profile and opens home', (tester) async {
    await start(tester);
    await seedAccount(tester);
    await settle(tester);

    await login(tester, 'amel@esprit.tn', 'secret123');

    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('HOME:Amel Ben Salah'), findsOneWidget);
    expect(store.all(DeviceSessionService.loginsCollection), isNotEmpty);
  });

  flowTest('wrong password keeps the user on the login screen with a message', (tester) async {
    await start(tester);
    await seedAccount(tester);
    await settle(tester);

    await login(tester, 'amel@esprit.tn', 'nope1234');

    expect(find.text('Email ou mot de passe incorrect.'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(provider.status, AuthStatus.visitor);
  });

  flowTest('after 5 wrong passwords the login is locked and points to the admin reset', (tester) async {
    await start(tester);
    await seedAccount(tester);
    await settle(tester);

    await login(tester, 'amel@esprit.tn', 'nope1234');
    for (var i = 0; i < AuthService.maxFailedAttempts; i++) {
      await tapText(tester, 'Se connecter');
      await settle(tester);
    }
    expect(find.text('Trop de tentatives. Réessayez dans 5 minutes.'), findsOneWidget);

    await tapText(tester, 'Réinitialiser le mot de passe');
    await tester.pumpAndSettle();
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    expect(find.textContaining('administrateur'), findsWidgets);
  });

  flowTest('a disabled account cannot log in', (tester) async {
    await start(tester);
    await seedAccount(tester, profile: {'disabled': true});
    await settle(tester);

    await login(tester, 'amel@esprit.tn', 'secret123');

    expect(find.text('Ce compte a été désactivé.'), findsOneWidget);
    expect(provider.status, AuthStatus.visitor);
  });

  flowTest('with two-factor on, login asks for the code before home', (tester) async {
    await start(tester);
    await seedAccount(
      tester,
      profile: {'twoFactorEnabled': true, 'isPhoneVerified': true, 'phoneNumber': '+21620123456'},
    );
    await settle(tester);

    await login(tester, 'amel@esprit.tn', 'secret123');
    expect(find.text('2FA'), findsOneWidget);
    expect(provider.twoFactorRequired, isTrue);

    await provider.sendPhoneOtp('+21620123456');
    await provider.verifyPhoneOtp(provider.demoSmsCode!);
    await settle(tester);

    expect(find.text('HOME:Amel Ben Salah'), findsOneWidget);
    expect(service.twoFactorPending, isFalse);
  });

  flowTest('an open session is restored at start-up', (tester) async {
    await start(
      tester,
      before: () async {
        await service.registerWithEmail(email: 'amel@esprit.tn', password: 'secret123', fullName: 'Amel Ben Salah');
      },
    );

    expect(find.text('HOME:Amel Ben Salah'), findsOneWidget);
  });

  flowTest('logout returns to the visitor page', (tester) async {
    await start(
      tester,
      before: () async {
        await service.registerWithEmail(email: 'amel@esprit.tn', password: 'secret123', fullName: 'Amel Ben Salah');
      },
    );
    expect(provider.status, AuthStatus.authenticated);

    await provider.logout();
    await settle(tester);

    expect(find.text('VISITOR'), findsOneWidget);
    expect(service.currentAccount, isNull);
  });

  flowTest('duplicate email on register shows the error and creates no profile', (tester) async {
    await start(tester);
    await seedAccount(tester, fullName: 'Amel Premier');
    await settle(tester);

    await tester.tap(find.text('go-register'));
    await tester.pumpAndSettle();
    await enterField(tester, 0, 'Amel Test');
    await enterField(tester, 1, 'amel@esprit.tn');
    await enterField(tester, 3, 'secret123');
    await enterField(tester, 4, 'secret123');
    await tapText(tester, 'Créer mon compte');
    await settle(tester);

    expect(find.text('Cet email est déjà utilisé.'), findsOneWidget);
    expect(store.all(AppConstants.usersCollection), hasLength(1));
    expect(store.where(AppConstants.usersCollection, (d) => d['fullName'] == 'Amel Test'), isEmpty);
  });
}
