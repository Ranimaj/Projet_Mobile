import 'package:campusconnect/core/theme/app_tokens.dart';
import 'package:campusconnect/core/utils/auth_failure.dart';
import 'package:campusconnect/widgets/auth/auth_feedback.dart';
import 'package:campusconnect/widgets/auth/password_strength_meter.dart';
import 'package:campusconnect/widgets/auth/auth_hero.dart';
import 'package:campusconnect/widgets/auth/auth_text_field.dart';
import 'package:campusconnect/widgets/hero_sheet_scaffold.dart';
import 'package:campusconnect/widgets/pill_button.dart';
import 'package:flutter/material.dart';
import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/screens/auth/otp_verification_screen.dart';
import 'package:campusconnect/screens/auth/register_screen.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';
import '../helpers/pump_app.dart';
import '../helpers/pump_themed.dart';

void main() {
  late MockAuthService service;
  late AuthProvider provider;

  final created = AppUser(
    id: 'uid-1',
    fullName: 'Amel Ben Salah',
    email: 'amel@esprit.tn',
    createdAt: DateTime(2025, 1, 1),
  );

  void stubRegister() {
    when(() => service.registerWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
          fullName: any(named: 'fullName'),
        )).thenAnswer((_) async => created);
    when(() => service.sendEmailVerification()).thenAnswer((_) async {});
  }

  Future<void> fillValid(WidgetTester tester, {String phone = ''}) async {
    await enterField(tester, 0, 'amel ben salah');
    await enterField(tester, 1, 'amel@esprit.tn');
    if (phone.isNotEmpty) await enterField(tester, 2, phone);
    await enterField(tester, 3, 'secret123');
    await enterField(tester, 4, 'secret123');
  }

  setUp(() {
    service = MockAuthService();
    when(() => service.authStateChanges).thenAnswer((_) => const Stream<User?>.empty());
    provider = AuthProvider(authService: service);
  });

  tearDown(() => provider.dispose());

  testWidgets('validates every field', (tester) async {
    await pumpAuthScreen(tester, provider, const RegisterScreen());

    await tapText(tester, 'Créer mon compte');
    await tester.pump();

    expect(find.text('Nom requis'), findsOneWidget);
    expect(find.text('Email requis'), findsOneWidget);
    expect(find.text('Mot de passe requis'), findsOneWidget);
    expect(find.text('Confirmation requise'), findsOneWidget);
    verifyNever(() => service.registerWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
          fullName: any(named: 'fullName'),
        ));
  });

  testWidgets('enforces password rules and confirmation match', (tester) async {
    await pumpAuthScreen(tester, provider, const RegisterScreen());

    await enterField(tester, 3, 'abc123');
    await enterField(tester, 4, 'different');
    await tapText(tester, 'Créer mon compte');
    await tester.pump();

    expect(find.text('8 caractères minimum'), findsOneWidget);
    expect(find.text('Les mots de passe ne correspondent pas'), findsOneWidget);
  });

  testWidgets('validates the optional phone only when filled', (tester) async {
    await pumpAuthScreen(tester, provider, const RegisterScreen());

    await fillValid(tester, phone: '12');
    await tapText(tester, 'Créer mon compte');
    await tester.pump();

    expect(find.text('Numéro invalide (ex. 20 123 456)'), findsOneWidget);
    verifyNever(() => service.registerWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
          fullName: any(named: 'fullName'),
        ));
  });

  testWidgets('shows the password strength as the user types', (tester) async {
    await pumpAuthScreen(tester, provider, const RegisterScreen());

    expect(find.textContaining('Robustesse'), findsNothing);
    await enterField(tester, 3, 'abc');
    await tester.pump();
    expect(find.text('Robustesse : Faible'), findsOneWidget);

    await enterField(tester, 3, 'Abcdefg1!');
    await tester.pump();
    expect(find.text('Robustesse : Excellent'), findsOneWidget);
  });

  testWidgets('registers without a phone and closes the screen', (tester) async {
    stubRegister();
    await pumpAuthScreen(tester, provider, const RegisterScreen());

    await fillValid(tester);
    await tapText(tester, 'Créer mon compte');
    await tester.pumpAndSettle();

    verify(() => service.registerWithEmail(
          email: 'amel@esprit.tn',
          password: 'secret123',
          fullName: 'amel ben salah',
        )).called(1);
    verify(() => service.sendEmailVerification()).called(1);
    expect(find.byType(RegisterScreen), findsNothing);
    expect(find.byType(OtpVerificationScreen), findsNothing);
  });

  testWidgets('continues to OTP verification when a phone is provided', (tester) async {
    stubRegister();
    when(() => service.sendPhoneOtp(any())).thenAnswer((_) async => '+21620123456');
    await pumpAuthScreen(tester, provider, const RegisterScreen());

    await fillValid(tester, phone: '20 123 456');
    await tapText(tester, 'Créer mon compte');
    await tester.pumpAndSettle();

    expect(find.byType(OtpVerificationScreen), findsOneWidget);
    verify(() => service.sendPhoneOtp('20 123 456')).called(1);
  });

  testWidgets('shows the error and stays on the form when the email is taken', (tester) async {
    when(() => service.registerWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
          fullName: any(named: 'fullName'),
        )).thenThrow(AuthFailure.fromCode('email-already-in-use'));
    await pumpAuthScreen(tester, provider, const RegisterScreen());

    await fillValid(tester);
    await tapText(tester, 'Créer mon compte');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Cet email est déjà utilisé.'), findsOneWidget);
    expect(find.byType(RegisterScreen), findsOneWidget);
    verifyNever(() => service.sendEmailVerification());
  });

  group('UI contract (hero sheet)', () {
    testWidgets('is built from HeroSheetScaffold with an AuthHero and no GradientScaffold', (tester) async {
      await pumpAuthScreen(tester, provider, const RegisterScreen());

      expect(find.byType(HeroSheetScaffold), findsOneWidget);
      expect(find.byType(AuthHero), findsOneWidget);
      expect(find.byType(AuthTextField), findsNWidgets(5));
      expect(find.widgetWithText(PillButton, 'Créer mon compte'), findsOneWidget);
      expect(find.byType(AutofillGroup), findsOneWidget);

      expect(find.text('Rejoindre CampusConnect'), findsOneWidget);
      expect(find.text('Utilise ton email académique pour être vérifié'), findsOneWidget);
      expect(find.byIcon(Icons.person_add_alt_1_rounded), findsOneWidget);
      for (final label in ['Nom complet', 'Email académique', 'Téléphone (optionnel)', 'Mot de passe', 'Confirmer le mot de passe']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.text('Pour vérifier ton compte par SMS, juste après l\'inscription.'), findsOneWidget);
    });

    testWidgets('the main action is a primary PillButton that spans the sheet', (tester) async {
      await pumpAuthScreen(tester, provider, const RegisterScreen());

      final finder = find.widgetWithText(PillButton, 'Créer mon compte');
      await tester.ensureVisible(finder);
      expect(tester.widget<PillButton>(finder).style, PillStyle.primary);
      expect(tester.getSize(finder).width, 420 - 2 * 20);
    });

    testWidgets('field errors use the danger token and the banner the dangerSoft one', (tester) async {
      when(() => service.registerWithEmail(
            email: any(named: 'email'),
            password: any(named: 'password'),
            fullName: any(named: 'fullName'),
          )).thenThrow(AuthFailure.fromCode('email-already-in-use'));
      await pumpAuthScreen(tester, provider, const RegisterScreen());

      await tapText(tester, 'Créer mon compte');
      await tester.pump();
      expect(tester.widget<Text>(find.text('Nom requis')).style!.color, AppTokens.light.danger);

      await fillValid(tester);
      await tapText(tester, 'Créer mon compte');
      await tester.pumpAndSettle();
      final banner = tester.widget<AuthErrorBanner>(find.byType(AuthErrorBanner));
      expect(banner.message, 'Cet email est déjà utilisé.');
      expect(tester.widget<Text>(find.text('Cet email est déjà utilisé.')).style!.color, AppTokens.light.danger);
    });

    testWidgets('keyboard open shrinks the hero to 120 dp at 360x640', (tester) async {
      await pumpAuthScreen(tester, provider, const RegisterScreen(),
          size: const Size(360, 640), keyboardInset: 300);
      expect(tester.getSize(find.byType(AuthHero)).height, 120);
    });

    testWidgets('the strength meter uses the token palette', (tester) async {
      await pumpAuthScreen(tester, provider, const RegisterScreen());

      await enterField(tester, 3, 'abc');
      await tester.pump();
      expect(tester.widget<Text>(find.textContaining('Robustesse :')).style!.color, AppTokens.light.textSecondary);
      final segments = tester
          .widgetList<AnimatedContainer>(find.descendant(
              of: find.byType(PasswordStrengthMeter), matching: find.byType(AnimatedContainer)))
          .map((c) => (c.decoration! as BoxDecoration).color);
      expect(segments, contains(AppTokens.light.danger));
    });

    testWidgets('"J\'ai déjà un compte" is a primary underlined link that goes back', (tester) async {
      await pumpAuthScreen(tester, provider, const RegisterScreen());

      final style = tester.widget<Text>(find.text('J\'ai déjà un compte')).style!;
      expect(style.color, AppTokens.light.primary);
      expect(style.decoration, TextDecoration.underline);

      await tapText(tester, 'J\'ai déjà un compte');
      await tester.pumpAndSettle();
      expect(find.byType(RegisterScreen), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    for (final brightness in Brightness.values) {
      testWidgets('no text under 13 px in ${brightness.name}', (tester) async {
        await pumpAuthScreen(tester, provider, const RegisterScreen(), brightness: brightness);
        expectNoSmallText(tester);
      });
    }

    testWidgets('fields carry the right keyboard, capitalisation and autofill settings', (tester) async {
      await pumpAuthScreen(tester, provider, const RegisterScreen());
      final f = tester.widgetList<TextField>(find.byType(TextField)).toList();

      expect(f[0].textCapitalization, TextCapitalization.words);
      expect(f[0].autofillHints, contains(AutofillHints.name));
      expect(f[1].keyboardType, TextInputType.emailAddress);
      expect(f[1].autofillHints, contains(AutofillHints.email));
      expect(f[2].keyboardType, TextInputType.phone);
      expect(f[2].autofillHints, contains(AutofillHints.telephoneNumber));
      expect(f[3].obscureText, isTrue);
      expect(f[3].autofillHints, contains(AutofillHints.newPassword));
      expect(f[4].obscureText, isTrue);
      expect(f[4].textInputAction, TextInputAction.done);
      expect(f.where((t) => t.textInputAction == TextInputAction.next).length, 4);
    });

    testWidgets('keyboard "done" on the confirmation submits the form', (tester) async {
      stubRegister();
      await pumpAuthScreen(tester, provider, const RegisterScreen());
      await fillValid(tester);

      await tester.tap(find.byType(TextFormField).at(4));
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      verify(() => service.registerWithEmail(
            email: 'amel@esprit.tn',
            password: 'secret123',
            fullName: 'amel ben salah',
          )).called(1);
    });
  });
}
