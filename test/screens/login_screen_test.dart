import 'dart:async';

import 'package:campusconnect/core/theme/app_tokens.dart';
import 'package:campusconnect/core/utils/auth_failure.dart';
import 'package:campusconnect/widgets/auth/auth_feedback.dart';
import 'package:campusconnect/services/app_prefs.dart';
import 'package:campusconnect/widgets/auth/auth_hero.dart';
import 'package:campusconnect/widgets/auth/auth_text_field.dart';
import 'package:campusconnect/widgets/hero_sheet_scaffold.dart';
import 'package:campusconnect/widgets/pill_button.dart';
import 'package:campusconnect/widgets/social_icon_row.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/screens/auth/forgot_password_screen.dart';
import 'package:campusconnect/screens/auth/login_screen.dart';
import 'package:campusconnect/screens/auth/register_screen.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/mocks.dart';
import '../helpers/pump_app.dart';
import '../helpers/pump_themed.dart';

class _FakeCredential extends Mock implements UserCredential {}

void main() {
  late MockAuthService service;
  late AuthProvider provider;

  setUp(() {
    service = MockAuthService();
    when(() => service.authStateChanges).thenAnswer((_) => const Stream<User?>.empty());
    provider = AuthProvider(authService: service);
  });

  tearDown(() => provider.dispose());

  testWidgets('shows required-field errors and does not call the service', (tester) async {
    await pumpAuthScreen(tester, provider, const LoginScreen());

    await tapText(tester, 'Se connecter');
    await tester.pump();

    expect(find.text('Email requis'), findsOneWidget);
    expect(find.text('Mot de passe requis'), findsOneWidget);
    verifyNever(() => service.signInWithEmail(any(), any()));
  });

  testWidgets('rejects a malformed email', (tester) async {
    await pumpAuthScreen(tester, provider, const LoginScreen());

    await enterField(tester, 0, 'not-an-email');
    await enterField(tester, 1, 'secret123');
    await tapText(tester, 'Se connecter');
    await tester.pump();

    expect(find.text('Email invalide'), findsOneWidget);
    verifyNever(() => service.signInWithEmail(any(), any()));
  });

  testWidgets('logs in and closes the auth screens on success', (tester) async {
    when(() => service.signInWithEmail(any(), any())).thenAnswer((_) async => _FakeCredential());
    await pumpAuthScreen(tester, provider, const LoginScreen());

    await enterField(tester, 0, 'amel@esprit.tn');
    await enterField(tester, 1, 'secret123');
    await tapText(tester, 'Se connecter');
    await tester.pumpAndSettle();

    verify(() => service.signInWithEmail('amel@esprit.tn', 'secret123')).called(1);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('shows the mapped error message when login fails', (tester) async {
    when(() => service.signInWithEmail(any(), any()))
        .thenThrow(AuthFailure.fromCode('invalid-credential'));
    await pumpAuthScreen(tester, provider, const LoginScreen());

    await enterField(tester, 0, 'amel@esprit.tn');
    await enterField(tester, 1, 'wrongpass');
    await tapText(tester, 'Se connecter');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Email ou mot de passe incorrect.'), findsOneWidget);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('shows a spinner and blocks resubmission while loading', (tester) async {
    final gate = Completer<UserCredential>();
    when(() => service.signInWithEmail(any(), any())).thenAnswer((_) => gate.future);
    await pumpAuthScreen(tester, provider, const LoginScreen());

    await enterField(tester, 0, 'amel@esprit.tn');
    await enterField(tester, 1, 'secret123');
    await tapText(tester, 'Se connecter');
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(CircularProgressIndicator));
    await tester.pump();
    verify(() => service.signInWithEmail(any(), any())).called(1);

    gate.complete(_FakeCredential());
    await tester.pumpAndSettle();
  });

  testWidgets('password visibility toggle works', (tester) async {
    await pumpAuthScreen(tester, provider, const LoginScreen());

    EditableText passwordField() =>
        tester.widget<EditableText>(find.descendant(of: find.byType(TextFormField).at(1), matching: find.byType(EditableText)));

    expect(passwordField().obscureText, isTrue);
    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pump();
    expect(passwordField().obscureText, isFalse);
  });

  testWidgets('"Mot de passe oublié ?" opens the reset screen prefilled with the email', (tester) async {
    await pumpAuthScreen(tester, provider, const LoginScreen());

    await enterField(tester, 0, 'amel@esprit.tn');
    await tapText(tester, 'Mot de passe oublié ?');
    await tester.pumpAndSettle();

    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'amel@esprit.tn'), findsOneWidget);
  });

  testWidgets('"Créer un compte" opens the registration screen', (tester) async {
    await pumpAuthScreen(tester, provider, const LoginScreen());

    final link = find.textContaining('Créer un compte', findRichText: true);
    await tester.ensureVisible(link);
    await tester.tap(link);
    await tester.pumpAndSettle();

    expect(find.byType(RegisterScreen), findsOneWidget);
  });

  group('biometrics', () {
    testWidgets('the unlock button is hidden when the device has no usable biometrics', (tester) async {
      when(() => service.canUseBiometrics()).thenAnswer((_) async => false);
      await pumpAuthScreen(tester, provider, const LoginScreen());

      expect(find.byTooltip('Déverrouiller par biométrie'), findsNothing);
    });

    testWidgets('the unlock button is hidden without a remembered session', (tester) async {
      when(() => service.canUseBiometrics()).thenAnswer((_) async => true);
      when(() => service.hasRestorableSession).thenReturn(false);
      await pumpAuthScreen(tester, provider, const LoginScreen());

      expect(find.byTooltip('Déverrouiller par biométrie'), findsNothing);
    });

    testWidgets('a refused biometric prompt shows its message', (tester) async {
      when(() => service.canUseBiometrics()).thenAnswer((_) async => true);
      when(() => service.hasRestorableSession).thenReturn(true);
      when(() => service.authenticateWithBiometrics()).thenAnswer((_) async => false);
      await pumpAuthScreen(tester, provider, const LoginScreen());

      await tester.ensureVisible(find.byTooltip('Déverrouiller par biométrie'));
      await tester.tap(find.byTooltip('Déverrouiller par biométrie'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Authentification biométrique refusée ou indisponible.'), findsOneWidget);
    });
  });

  group('remember me', () {
    testWidgets('prefills the remembered email and stores it again after login', (tester) async {
      final prefs = FakeLoginPrefs(remembered: 'amel@esprit.tn');
      when(() => service.signInWithEmail(any(), any())).thenAnswer((_) async => _FakeCredential());
      await pumpAuthScreen(tester, provider, LoginScreen(prefs: prefs));

      expect(find.widgetWithText(TextFormField, 'amel@esprit.tn'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

      await enterField(tester, 1, 'secret123');
      await tapText(tester, 'Se connecter');
      await tester.pumpAndSettle();

      expect(prefs.writes, ['amel@esprit.tn']);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('unticking the box forgets the email', (tester) async {
      final prefs = FakeLoginPrefs(remembered: 'amel@esprit.tn');
      when(() => service.signInWithEmail(any(), any())).thenAnswer((_) async => _FakeCredential());
      await pumpAuthScreen(tester, provider, LoginScreen(prefs: prefs));

      await tapText(tester, 'Se souvenir de moi');
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

      await enterField(tester, 1, 'secret123');
      await tapText(tester, 'Se connecter');
      await tester.pumpAndSettle();

      expect(prefs.writes, [null]);
      expect(prefs.rememberedEmail, isNull);
    });

    testWidgets('nothing is stored when login fails', (tester) async {
      final prefs = FakeLoginPrefs();
      when(() => service.signInWithEmail(any(), any())).thenThrow(AuthFailure.fromCode('invalid-credential'));
      await pumpAuthScreen(tester, provider, LoginScreen(prefs: prefs));

      await enterField(tester, 0, 'amel@esprit.tn');
      await enterField(tester, 1, 'bad');
      await tapText(tester, 'Se connecter');
      await tester.pumpAndSettle();

      expect(prefs.writes, isEmpty);
    });
  });

  group('academic domain completion', () {
    testWidgets('offers the domain only while it is missing, and appends it', (tester) async {
      await pumpAuthScreen(tester, provider, const LoginScreen());
      expect(find.text('Compléter avec @esprit.tn'), findsNothing);

      await enterField(tester, 0, 'amel.bensalah');
      await tester.pumpAndSettle();
      expect(find.text('Compléter avec @esprit.tn'), findsOneWidget);

      await tapText(tester, 'Compléter avec @esprit.tn');
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'amel.bensalah@esprit.tn'), findsOneWidget);
      expect(find.text('Compléter avec @esprit.tn'), findsNothing);
    });

    testWidgets('is not offered once an @ is typed', (tester) async {
      await pumpAuthScreen(tester, provider, const LoginScreen());
      await enterField(tester, 0, 'amel@gmail.com');
      await tester.pumpAndSettle();
      expect(find.text('Compléter avec @esprit.tn'), findsNothing);
    });
  });

  group('error actions', () {
    testWidgets('a network error offers to retry', (tester) async {
      when(() => service.signInWithEmail(any(), any()))
          .thenThrow(AuthFailure.fromCode('network-request-failed'));
      await pumpAuthScreen(tester, provider, const LoginScreen());

      await enterField(tester, 0, 'amel@esprit.tn');
      await enterField(tester, 1, 'secret123');
      await tapText(tester, 'Se connecter');
      await tester.pumpAndSettle();
      expect(find.text('Pas de connexion réseau.'), findsOneWidget);

      // Le réseau revient : « Réessayer » relance la même connexion.
      when(() => service.signInWithEmail(any(), any())).thenAnswer((_) async => _FakeCredential());
      await tapText(tester, 'Réessayer');
      await tester.pumpAndSettle();

      verify(() => service.signInWithEmail('amel@esprit.tn', 'secret123')).called(2);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('too many attempts offers a password reset', (tester) async {
      when(() => service.signInWithEmail(any(), any())).thenThrow(AuthFailure.fromCode('too-many-requests'));
      await pumpAuthScreen(tester, provider, const LoginScreen());

      await enterField(tester, 0, 'amel@esprit.tn');
      await enterField(tester, 1, 'secret123');
      await tapText(tester, 'Se connecter');
      await tester.pumpAndSettle();

      await tapText(tester, 'Réinitialiser le mot de passe');
      await tester.pumpAndSettle();

      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'amel@esprit.tn'), findsOneWidget);
    });

    testWidgets('a wrong password offers no extra action', (tester) async {
      when(() => service.signInWithEmail(any(), any())).thenThrow(AuthFailure.fromCode('invalid-credential'));
      await pumpAuthScreen(tester, provider, const LoginScreen());

      await enterField(tester, 0, 'amel@esprit.tn');
      await enterField(tester, 1, 'bad');
      await tapText(tester, 'Se connecter');
      await tester.pumpAndSettle();

      expect(find.text('Réessayer'), findsNothing);
      expect(find.text('Réinitialiser le mot de passe'), findsNothing);
    });
  });

  testWidgets('a cancelled Google sign-in shows no error', (tester) async {
    when(() => service.signInWithGoogle()).thenAnswer((_) async => null);
    await pumpAuthScreen(tester, provider, const LoginScreen());

    await tester.ensureVisible(find.byTooltip('Continuer avec Google'));
    await tester.tap(find.byTooltip('Continuer avec Google'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  group('inline error banner', () {
    Future<void> failLogin(WidgetTester tester) async {
      when(() => service.signInWithEmail(any(), any()))
          .thenThrow(AuthFailure.fromCode('invalid-credential'));
      await pumpAuthScreen(tester, provider, const LoginScreen());
      await enterField(tester, 0, 'amel@esprit.tn');
      await enterField(tester, 1, 'wrongpass');
      await tapText(tester, 'Se connecter');
      await tester.pumpAndSettle();
      expect(find.text('Email ou mot de passe incorrect.'), findsOneWidget);
    }

    testWidgets('is shown in the card, not as a snackbar', (tester) async {
      await failLogin(tester);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('disappears as soon as the user edits a field', (tester) async {
      await failLogin(tester);

      await enterField(tester, 1, 'wrongpass2');
      await tester.pumpAndSettle();

      expect(find.text('Email ou mot de passe incorrect.'), findsNothing);
    });

    testWidgets('can be dismissed with its close button', (tester) async {
      await failLogin(tester);

      await tester.tap(find.byTooltip('Fermer'));
      await tester.pumpAndSettle();

      expect(find.text('Email ou mot de passe incorrect.'), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  group('UI contract (hero sheet)', () {
    EditableText editableAt(WidgetTester tester, int index) => tester.widget<EditableText>(
        find.descendant(of: find.byType(TextFormField).at(index), matching: find.byType(EditableText)));

    testWidgets('is built from HeroSheetScaffold with an AuthHero and no GradientScaffold', (tester) async {
      await pumpAuthScreen(tester, provider, const LoginScreen());

      expect(find.byType(HeroSheetScaffold), findsOneWidget);
      expect(find.byType(AuthHero), findsOneWidget);
      expect(find.byType(AuthTextField), findsNWidgets(2));
      expect(find.widgetWithText(PillButton, 'Se connecter'), findsOneWidget);
      expect(find.byType(SocialIconRow), findsOneWidget);
      expect(find.byType(AutofillGroup), findsOneWidget);

      expect(find.text('Bon retour'), findsOneWidget);
      expect(find.text('Connecte-toi avec ton email académique'), findsOneWidget);
      expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget);
      expect(find.text('Email académique'), findsOneWidget);
      expect(find.text('Mot de passe'), findsOneWidget);
      expect(find.text('Ou connectez-vous avec'), findsOneWidget);
      expect(find.byTooltip('Continuer avec Google'), findsOneWidget);
      // Reached from a pushed route: the hero carries a back button.
      expect(find.byTooltip('Retour'), findsOneWidget);
    });

    testWidgets('the main action is a primary PillButton that spans the sheet', (tester) async {
      await pumpAuthScreen(tester, provider, const LoginScreen());

      final pill = tester.widget<PillButton>(find.widgetWithText(PillButton, 'Se connecter'));
      expect(pill.style, PillStyle.primary);
      expect(pill.expand, isTrue);
      expect(tester.getSize(find.widgetWithText(PillButton, 'Se connecter')).width, 420 - 2 * 20);
    });

    testWidgets('field errors use the danger token', (tester) async {
      await pumpAuthScreen(tester, provider, const LoginScreen());
      await tapText(tester, 'Se connecter');
      await tester.pump();

      expect(tester.widget<Text>(find.text('Email requis')).style!.color, AppTokens.light.danger);
    });

    testWidgets('errors are shown in the dangerSoft banner', (tester) async {
      when(() => service.signInWithEmail(any(), any())).thenThrow(AuthFailure.fromCode('invalid-credential'));
      await pumpAuthScreen(tester, provider, const LoginScreen());

      await enterField(tester, 0, 'amel@esprit.tn');
      await enterField(tester, 1, 'bad');
      await tapText(tester, 'Se connecter');
      await tester.pumpAndSettle();

      final banner = tester.widget<AuthErrorBanner>(find.byType(AuthErrorBanner));
      expect(banner.message, 'Email ou mot de passe incorrect.');
      final text = tester.widget<Text>(find.text('Email ou mot de passe incorrect.'));
      expect(text.style!.color, AppTokens.light.danger);
    });

    testWidgets('keyboard open shrinks the hero to 120 dp at 360x640', (tester) async {
      await pumpAuthScreen(tester, provider, const LoginScreen(),
          size: const Size(360, 640), keyboardInset: 300);

      expect(tester.getSize(find.byType(AuthHero)).height, 120);
    });

    testWidgets('the links are primary, underlined text buttons; the checkbox uses the theme', (tester) async {
      await pumpAuthScreen(tester, provider, const LoginScreen());
      const tokens = AppTokens.light;

      final forgot = tester.widget<Text>(find.text('Mot de passe oublié ?')).style!;
      expect(forgot.color, tokens.primary);
      expect(forgot.decoration, TextDecoration.underline);

      final rich = tester.widget<RichText>(find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('Créer un compte')));
      final spans = <TextSpan>[];
      rich.text.visitChildren((s) {
        if (s is TextSpan) spans.add(s);
        return true;
      });
      final link = spans.firstWhere((s) => s.text == 'Créer un compte');
      expect(link.style!.color, tokens.primary);
      expect(link.style!.decoration, TextDecoration.underline);

      final cb = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(cb.value, isTrue);
      expect(cb.fillColor, isNull, reason: 'default theme fill');
      expect(cb.checkColor, isNull, reason: 'default theme check');
    });

    testWidgets('the biometric button is hidden when biometric_unlock is false', (tester) async {
      SharedPreferences.setMockInitialValues({'biometric_unlock': false});
      final appPrefs = AppPrefs(await SharedPreferences.getInstance());
      when(() => service.canUseBiometrics()).thenAnswer((_) async => true);
      when(() => service.hasRestorableSession).thenReturn(true);
      await pumpAuthScreen(tester, provider, LoginScreen(appPrefs: appPrefs));

      expect(find.byTooltip('Continuer avec Google'), findsOneWidget);
      expect(find.byTooltip('Déverrouiller par biométrie'), findsNothing);
    });

    testWidgets('the biometric button follows a provided AppPrefs when enabled', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final appPrefs = AppPrefs(await SharedPreferences.getInstance());
      when(() => service.canUseBiometrics()).thenAnswer((_) async => true);
      when(() => service.hasRestorableSession).thenReturn(true);
      await pumpAuthScreen(tester, provider, const LoginScreen(),
          wrap: (app) => Provider<AppPrefs>.value(value: appPrefs, child: app));

      expect(find.byTooltip('Déverrouiller par biométrie'), findsOneWidget);
    });

    for (final brightness in Brightness.values) {
      testWidgets('no text under 13 px in ${brightness.name}', (tester) async {
        await pumpAuthScreen(tester, provider, const LoginScreen(), brightness: brightness);
        expectNoSmallText(tester);
      });
    }

    testWidgets('keyboard "next" on the email focuses the password; "done" submits', (tester) async {
      when(() => service.signInWithEmail(any(), any())).thenAnswer((_) async => _FakeCredential());
      await pumpAuthScreen(tester, provider, const LoginScreen());

      await tester.tap(find.byType(TextFormField).first);
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).first, 'amel@esprit.tn');
      await tester.testTextInput.receiveAction(TextInputAction.next);
      await tester.pump();
      expect(editableAt(tester, 1).focusNode.hasFocus, isTrue);

      await tester.enterText(find.byType(TextFormField).at(1), 'secret123');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      verify(() => service.signInWithEmail('amel@esprit.tn', 'secret123')).called(1);
      expect(find.byType(LoginScreen), findsNothing);
    });

    testWidgets('fields carry the right autofill hints and keyboard types', (tester) async {
      await pumpAuthScreen(tester, provider, const LoginScreen());
      final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();

      expect(fields[0].keyboardType, TextInputType.emailAddress);
      expect(fields[0].autofillHints, containsAll([AutofillHints.email, AutofillHints.username]));
      expect(fields[0].textInputAction, TextInputAction.next);
      expect(fields[1].autofillHints, contains(AutofillHints.password));
      expect(fields[1].textInputAction, TextInputAction.done);
      expect(fields[1].obscureText, isTrue);
    });

    testWidgets('the Google button is disabled while a login is in flight', (tester) async {
      final gate = Completer<UserCredential>();
      when(() => service.signInWithEmail(any(), any())).thenAnswer((_) => gate.future);
      await pumpAuthScreen(tester, provider, const LoginScreen());

      await enterField(tester, 0, 'amel@esprit.tn');
      await enterField(tester, 1, 'secret123');
      await tapText(tester, 'Se connecter');
      await tester.pump();

      await tester.tap(find.byTooltip('Continuer avec Google'));
      await tester.pump();
      verifyNever(() => service.signInWithGoogle());

      gate.complete(_FakeCredential());
      await tester.pumpAndSettle();
    });
  });
}
