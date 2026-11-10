import 'dart:math';

import 'package:campusconnect/core/constants/app_constants.dart';
import 'package:campusconnect/core/theme/app_theme.dart';
import 'package:campusconnect/core/utils/local_database.dart';
import 'package:campusconnect/core/utils/password_hasher.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/screens/auth/otp_verification_screen.dart' show DemoSmsBanner;
import 'package:campusconnect/screens/security/confirm_device_screen.dart';
import 'package:campusconnect/services/auth_service.dart';
import 'package:campusconnect/services/device_session_service.dart';
import 'package:campusconnect/services/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/fake_two_factor_mailer.dart';
import '../helpers/local_db.dart';
import '../helpers/mocks.dart';

/// Écran de double authentification branché sur le vrai service (base
/// SQLite en mémoire) et un envoi d'email factice.
void main() {
  late LocalStore store;
  late FakeMailer mailer;
  late AuthService service;
  late AuthProvider provider;
  late DateTime now;

  /// Comme `testWidgets`, mais ferme la base dans le test lui-même (ses
  /// Futures appartiennent au temps simulé).
  void screenTest(String description, Future<void> Function(WidgetTester tester) body) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        // Démonte l'écran : son compte à rebours s'arrête.
        await tester.pumpWidget(const SizedBox());
        provider.dispose();
        await closeTestDatabase();
      }
    });
  }

  Future<void> start(WidgetTester tester, {bool smtp = true, bool failing = false}) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    sqfliteFfiInit();
    await LocalDatabase.open(factory: databaseFactoryFfiNoIsolate, path: inMemoryDatabasePath);
    store = LocalStore();
    mailer = FakeMailer()
      ..configured = smtp
      ..failing = failing;
    now = DateTime(2026, 3, 1, 10);
    service = AuthService(
      store: store,
      storage: MockStorageService(),
      hasher: PasswordHasher(iterations: 1),
      random: Random(3),
      clock: () => now,
      mailer: mailer,
    );
    final user = await service.registerWithEmail(email: 'amel@esprit.tn', password: 'secret123', fullName: 'Amel Test');
    await store.update(AppConstants.usersCollection, user.id, {
      'twoFactorEnabled': true,
      'isPhoneVerified': true,
      'phoneNumber': '+21620123456',
    });
    await service.signOut();
    await service.signInWithEmail('amel@esprit.tn', 'secret123');

    provider = AuthProvider(
      authService: service,
      deviceSessionService: DeviceSessionService(
        store: store,
        deviceInfo: () async => (name: 'Pixel test', platform: 'android'),
        city: () async => null,
      ),
    );
    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
      value: provider,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Consumer<AuthProvider>(
          builder: (context, auth, child) => switch (auth.status) {
            AuthStatus.authenticated when auth.twoFactorRequired => const ConfirmDeviceScreen(),
            AuthStatus.authenticated => const Scaffold(body: Text('HOME')),
            _ => const Scaffold(body: Text('VISITOR')),
          },
        ),
      ),
    ));
    // Pas de pumpAndSettle : le compte à rebours du renvoi tourne.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> enterCode(WidgetTester tester, String code) async {
    await tester.enterText(find.byKey(const Key('otp-field')), code);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  String wrongCode() => mailer.lastCode == '000000' ? '111111' : '000000';

  screenTest('the code is e-mailed: no simulated SMS, the masked address is shown', (tester) async {
    await start(tester);

    expect(mailer.sent, hasLength(1));
    expect(mailer.sent.single.to, 'amel@esprit.tn');
    expect(find.textContaining('Code envoyé à a•••@esprit.tn'), findsWidgets);
    expect(find.byType(DemoSmsBanner), findsNothing);
    expect(find.textContaining(mailer.lastCode), findsNothing);
    expect(ConfirmDeviceScreen.maskEmail('amel@esprit.tn'), 'a•••@esprit.tn');
  });

  screenTest('a wrong code shows the remaining attempts; the right code opens home', (tester) async {
    await start(tester);

    await enterCode(tester, wrongCode());
    expect(find.text('Code incorrect. Encore 4 essais.'), findsOneWidget);
    expect(find.text('HOME'), findsNothing);

    await enterCode(tester, mailer.lastCode);
    expect(find.text('HOME'), findsOneWidget);
    expect(service.twoFactorPending, isFalse);
  });

  screenTest('resend is offered after 30 seconds and the new code works', (tester) async {
    await start(tester);
    final resend = find.byKey(const Key('confirm-device-resend'));
    expect(find.text('Renvoyer le code dans 30 s'), findsOneWidget);
    expect(tester.widget<TextButton>(resend).onPressed, isNull);

    now = now.add(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Renvoyer le code'), findsOneWidget);

    final first = mailer.lastCode;
    await tester.tap(resend);
    await tester.pump();
    await tester.pump();
    expect(mailer.sent, hasLength(2));
    expect(find.text('Renvoyer le code dans 30 s'), findsOneWidget);

    if (first != mailer.lastCode) {
      await enterCode(tester, first);
      expect(find.text('Code incorrect. Encore 4 essais.'), findsOneWidget);
    }
    await enterCode(tester, mailer.lastCode);
    expect(find.text('HOME'), findsOneWidget);
  });

  screenTest('a failed send shows a French error and a retry button', (tester) async {
    await start(tester, failing: true);

    expect(mailer.sent, isEmpty);
    expect(find.text("Le code n'a pas pu être envoyé par email. Vérifiez la connexion internet puis réessayez."),
        findsOneWidget);
    expect(find.textContaining('Code non envoyé'), findsWidgets);
    expect(find.text('Annuler et se déconnecter'), findsOneWidget);

    mailer.failing = false;
    await tester.tap(find.text('Réessayer'));
    await tester.pump();
    await tester.pump();
    expect(mailer.sent, hasLength(1));
    expect(find.textContaining('Code envoyé à a•••@esprit.tn'), findsWidgets);

    await enterCode(tester, mailer.lastCode);
    expect(find.text('HOME'), findsOneWidget);
  });

  screenTest('without SMTP the simulated code is shown, as before', (tester) async {
    await start(tester, smtp: false);

    expect(mailer.sent, isEmpty);
    expect(find.byType(DemoSmsBanner), findsOneWidget);
    expect(find.textContaining('Code envoyé'), findsNothing);
    await enterCode(tester, service.demoSmsCode!);
    expect(find.text('HOME'), findsOneWidget);
  });
}
