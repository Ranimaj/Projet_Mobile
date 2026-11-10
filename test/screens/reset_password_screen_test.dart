import 'dart:math';

import 'package:campusconnect/core/theme/app_theme.dart';
import 'package:campusconnect/core/utils/local_database.dart';
import 'package:campusconnect/core/utils/password_hasher.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/screens/auth/forgot_password_screen.dart';
import 'package:campusconnect/screens/auth/login_screen.dart';
import 'package:campusconnect/screens/auth/reset_password_screen.dart';
import 'package:campusconnect/services/auth_service.dart';
import 'package:campusconnect/services/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/fake_two_factor_mailer.dart';
import '../helpers/local_db.dart';
import '../helpers/mocks.dart';
import '../helpers/pump_app.dart';

/// Écrans « Mot de passe oublié » et « Nouveau mot de passe », branchés sur
/// le vrai service (base SQLite en mémoire) et un envoi d'email factice.
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
        await tester.pumpWidget(const SizedBox()); // arrête le compte à rebours
        provider.dispose();
        await closeTestDatabase();
      }
    });
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Ouvre « Mot de passe oublié » depuis un écran qui affiche ce que
  /// l'écran renvoie en se fermant.
  Future<void> start(WidgetTester tester, {bool smtp = true, bool failing = false, String email = ''}) async {
    tester.view.physicalSize = const Size(420, 1400);
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
      random: Random(5),
      clock: () => now,
      mailer: mailer,
    );
    await service.registerWithEmail(email: 'amel@esprit.tn', password: 'secret123', fullName: 'Amel Test');
    await store.set(AuthService.accountsCollection, 'demo-sarra', {
      'email': 'sarra.demo@esprit.tn',
      'password': PasswordHasher(iterations: 1).hash('demo1234').toMap(),
    });
    await service.signOut();
    provider = AuthProvider(authService: service);

    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
      value: provider,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  final result = await Navigator.of(context).push<String>(
                    MaterialPageRoute(builder: (_) => ForgotPasswordScreen(initialEmail: email)),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('RETOUR ${result ?? '-'}')));
                  }
                },
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('ouvrir'));
    await settle(tester);
  }

  Future<void> requestCode(WidgetTester tester, String email) async {
    await tester.enterText(find.descendant(of: find.byKey(const Key('forgot-email')), matching: find.byType(EditableText)), email);
    await tester.tap(find.byKey(const Key('forgot-send')));
    await settle(tester);
  }

  Future<void> fillReset(WidgetTester tester, {required String code, String password = 'nouveau456', String? confirm}) async {
    await tester.enterText(find.byKey(const Key('otp-field')), code);
    await tester.enterText(
        find.descendant(of: find.byKey(const Key('reset-password')), matching: find.byType(EditableText)), password);
    await tester.enterText(
        find.descendant(of: find.byKey(const Key('reset-confirm')), matching: find.byType(EditableText)),
        confirm ?? password);
    final submit = find.byKey(const Key('reset-submit'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await settle(tester);
  }

  String wrongCode() => mailer.lastCode == '000000' ? '111111' : '000000';

  screenTest('adresse sans compte : message neutre, aucun email', (tester) async {
    await start(tester);
    expect(find.byKey(const Key('forgot-send')), findsOneWidget);

    await requestCode(tester, 'personne@esprit.tn');

    expect(mailer.sent, isEmpty);
    expect(find.byType(ResetPasswordScreen), findsOneWidget);
    expect(find.text(ResetPasswordScreen.neutralMessage), findsWidgets);
    expect(find.textContaining('Si un compte existe pour personne@esprit.tn', findRichText: true), findsOneWidget);
  });

  screenTest('compte existant : même message ; code faux compté, bon code → retour avec l’email', (tester) async {
    await start(tester, email: 'Amel@Esprit.tn');
    await tester.tap(find.byKey(const Key('forgot-send')));
    await settle(tester);

    expect(mailer.sent, hasLength(1));
    expect(find.text(ResetPasswordScreen.neutralMessage), findsWidgets);
    expect(find.textContaining('Si un compte existe pour amel@esprit.tn', findRichText: true), findsOneWidget);
    expect(find.textContaining(mailer.lastCode), findsNothing);
    expect(find.text('Renvoyer le code dans 30 s'), findsOneWidget);
    expect(tester.widget<TextButton>(find.byKey(const Key('reset-resend'))).onPressed, isNull);

    await fillReset(tester, code: wrongCode());
    expect(find.text('Code incorrect. Encore 4 essais.'), findsOneWidget);

    await fillReset(tester, code: mailer.lastCode);
    expect(find.byType(ResetPasswordScreen), findsNothing);
    expect(find.byType(ForgotPasswordScreen), findsNothing);
    expect(find.text('RETOUR amel@esprit.tn'), findsOneWidget);
    await service.signInWithEmail('amel@esprit.tn', 'nouveau456');
  });

  screenTest('confirmation différente ou mot de passe faible : refusés avant le code', (tester) async {
    await start(tester, email: 'amel@esprit.tn');
    await tester.tap(find.byKey(const Key('forgot-send')));
    await settle(tester);

    await fillReset(tester, code: mailer.lastCode, password: 'nouveau456', confirm: 'nouveau457');
    expect(find.text('Les mots de passe ne correspondent pas'), findsOneWidget);
    await fillReset(tester, code: mailer.lastCode, password: 'court');
    expect(find.text('8 caractères minimum'), findsWidgets);
    expect(find.byType(ResetPasswordScreen), findsOneWidget);

    await fillReset(tester, code: mailer.lastCode);
    expect(find.text('RETOUR amel@esprit.tn'), findsOneWidget);
  });

  screenTest('5 codes faux : message de blocage', (tester) async {
    await start(tester, email: 'amel@esprit.tn');
    await tester.tap(find.byKey(const Key('forgot-send')));
    await settle(tester);
    for (var i = 0; i < 4; i++) {
      await fillReset(tester, code: wrongCode());
    }
    expect(find.text('Code incorrect. Dernier essai avant un blocage de 5 minutes.'), findsOneWidget);
    await fillReset(tester, code: wrongCode());
    expect(find.text("Trop d'essais. Nouvel essai possible dans 5 min."), findsOneWidget);
  });

  screenTest('code expiré : message clair', (tester) async {
    await start(tester, email: 'amel@esprit.tn');
    await tester.tap(find.byKey(const Key('forgot-send')));
    await settle(tester);
    now = now.add(const Duration(minutes: 10));
    await fillReset(tester, code: mailer.lastCode);
    expect(find.text('Le code a expiré. Demandez-en un nouveau.'), findsOneWidget);
  });

  screenTest('envoi impossible : erreur en français et « Réessayer »', (tester) async {
    await start(tester, email: 'amel@esprit.tn', failing: true);
    await tester.tap(find.byKey(const Key('forgot-send')));
    await settle(tester);

    expect(find.byType(ResetPasswordScreen), findsNothing);
    expect(find.text("Le code n'a pas pu être envoyé par email. Vérifiez la connexion internet puis réessayez."),
        findsOneWidget);
    final retry = find.text('Réessayer');
    expect(retry, findsOneWidget);

    mailer.failing = false;
    await tester.tap(retry);
    await settle(tester);
    expect(mailer.sent, hasLength(1));
    expect(find.byType(ResetPasswordScreen), findsOneWidget);
  });

  screenTest('SMTP non configuré : réinitialisation par un administrateur, annoncée', (tester) async {
    await start(tester, smtp: false, email: 'amel@esprit.tn');

    expect(find.byKey(const Key('forgot-email')), findsNothing);
    expect(find.textContaining("L'envoi d'emails n'est pas configuré"), findsOneWidget);
    for (final step in ForgotPasswordScreen.steps) {
      expect(find.text(step), findsOneWidget);
    }
  });

  screenTest('compte de démonstration : réinitialisation par un administrateur', (tester) async {
    await start(tester);
    await requestCode(tester, 'sarra.demo@esprit.tn');

    expect(mailer.sent, isEmpty);
    expect(find.byType(ResetPasswordScreen), findsNothing);
    expect(find.text(ForgotPasswordScreen.demoNote), findsOneWidget);
    expect(find.text(ForgotPasswordScreen.steps.first), findsOneWidget);
  });

  group('écran de connexion', () {
    late MockAuthService mock;
    late AuthProvider mocked;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mock = MockAuthService();
      when(() => mock.authStateChanges).thenAnswer((_) => const Stream<AuthAccount?>.empty());
      when(() => mock.passwordResetByEmail).thenReturn(true);
      when(() => mock.requestPasswordReset(any(), resend: any(named: 'resend'))).thenAnswer((_) async =>
          PasswordResetRequest(email: 'amel@esprit.tn', resendIn: Duration.zero, expiresAt: DateTime(2026)));
      when(() => mock.resetPasswordWithEmailCode(
          email: any(named: 'email'),
          code: any(named: 'code'),
          newPassword: any(named: 'newPassword'))).thenAnswer((_) async {});
      mocked = AuthProvider(authService: mock);
    });

    tearDown(() => mocked.dispose());

    testWidgets('après le changement : message de succès, email rempli', (tester) async {
      await pumpAuthScreen(tester, mocked, const LoginScreen(), size: const Size(420, 1400));
      await tester.tap(find.text('Mot de passe oublié ?'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(of: find.byKey(const Key('forgot-email')), matching: find.byType(EditableText)),
          'amel@esprit.tn');
      await tester.tap(find.byKey(const Key('forgot-send')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('otp-field')), '123456');
      await tester.enterText(
          find.descendant(of: find.byKey(const Key('reset-password')), matching: find.byType(EditableText)),
          'nouveau456');
      await tester.enterText(
          find.descendant(of: find.byKey(const Key('reset-confirm')), matching: find.byType(EditableText)),
          'nouveau456');
      await tester.ensureVisible(find.byKey(const Key('reset-submit')));
      await tester.tap(find.byKey(const Key('reset-submit')));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(ResetPasswordScreen), findsNothing);
      expect(find.text('Mot de passe modifié. Connecte-toi avec ton nouveau mot de passe.'), findsOneWidget);
      expect(find.text('amel@esprit.tn'), findsOneWidget);
      verify(() => mock.resetPasswordWithEmailCode(email: 'amel@esprit.tn', code: '123456', newPassword: 'nouveau456'))
          .called(1);
    });
  });
}
