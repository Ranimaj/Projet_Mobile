import 'dart:async';
import 'package:campusconnect/core/utils/auth_failure.dart';
import 'package:campusconnect/core/theme/app_tokens.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/widgets/auth/auth_hero.dart';
import 'package:campusconnect/widgets/auth/otp_input.dart';
import 'package:campusconnect/widgets/hero_sheet_scaffold.dart';
import 'package:campusconnect/widgets/pill_button.dart';
import 'package:campusconnect/screens/auth/otp_verification_screen.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';
import '../helpers/pump_app.dart';
import '../helpers/pump_themed.dart';

void main() {
  late MockAuthService service;
  late AuthProvider provider;

  setUp(() {
    service = MockAuthService();
    when(() => service.authStateChanges).thenAnswer((_) => const Stream<User?>.empty());
    when(() => service.sendPhoneOtp(any())).thenAnswer((_) async => '+21620123456');
    provider = AuthProvider(authService: service);
  });

  tearDown(() => provider.dispose());

  Future<void> typeCode(WidgetTester tester, String code) async {
    await tester.enterText(find.byKey(const Key('otp-field')), code);
    await tester.pump();
  }

  testWidgets('sends the code on open and shows the normalized number', (tester) async {
    await pumpAuthScreen(tester, provider, const OtpVerificationScreen(phone: '20123456'));

    verify(() => service.sendPhoneOtp('20123456')).called(1);
    expect(find.textContaining('Code envoyé au +21620123456'), findsOneWidget);
  });

  testWidgets('auto-verifies when 6 digits are entered and closes on success', (tester) async {
    when(() => service.verifyPhoneOtp(any())).thenAnswer((_) async {});
    await pumpAuthScreen(tester, provider, const OtpVerificationScreen(phone: '20123456'));

    await typeCode(tester, '123456');
    await tester.pumpAndSettle();

    verify(() => service.verifyPhoneOtp('123456')).called(1);
    expect(find.byType(OtpVerificationScreen), findsNothing);
  });

  testWidgets('does not verify before the code is complete', (tester) async {
    await pumpAuthScreen(tester, provider, const OtpVerificationScreen(phone: '20123456'));

    await typeCode(tester, '123');
    await tester.pump();

    verifyNever(() => service.verifyPhoneOtp(any()));
  });

  testWidgets('keeps only digits and at most 6 characters', (tester) async {
    await pumpAuthScreen(tester, provider, const OtpVerificationScreen(phone: '20123456'));

    await typeCode(tester, '12a4-5678');
    final field = tester.widget<TextField>(find.byKey(const Key('otp-field')));
    expect(field.controller!.text, '124567');
  });

  testWidgets('shows an error and stays when the code is wrong', (tester) async {
    when(() => service.verifyPhoneOtp(any())).thenThrow(AuthFailure.fromCode('invalid-verification-code'));
    await pumpAuthScreen(tester, provider, const OtpVerificationScreen(phone: '20123456'));

    await typeCode(tester, '000000');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Code incorrect. Vérifiez et réessayez.'), findsOneWidget);
    expect(find.byType(OtpVerificationScreen), findsOneWidget);
  });

  testWidgets('resend is locked during the countdown, then resends', (tester) async {
    await pumpAuthScreen(
      tester,
      provider,
      const OtpVerificationScreen(phone: '20123456', resendDelay: Duration(seconds: 3)),
    );

    expect(find.text('Renvoyer le code dans 3 s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Renvoyer le code dans 2 s'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Renvoyer le code'), findsOneWidget);

    await tester.tap(find.text('Renvoyer le code'));
    await tester.pump();
    await tester.pump();
    verify(() => service.sendPhoneOtp('20123456')).called(2);
    expect(find.text('Renvoyer le code dans 3 s'), findsOneWidget);

    // Laisse le timer se terminer avant la fin du test.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('reports a failure to send the code and keeps input disabled', (tester) async {
    when(() => service.sendPhoneOtp(any())).thenThrow(AuthFailure.fromCode('too-many-requests'));
    await pumpAuthScreen(tester, provider, const OtpVerificationScreen(phone: '20123456'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Trop de tentatives. Réessayez dans quelques minutes.'), findsOneWidget);
    final field = tester.widget<TextField>(find.byKey(const Key('otp-field')));
    expect(field.enabled, isFalse);
  });

  testWidgets('"Plus tard" skips verification when allowed', (tester) async {
    await pumpAuthScreen(tester, provider, const OtpVerificationScreen(phone: '20123456'));

    await tapText(tester, 'Plus tard');
    await tester.pumpAndSettle();

    expect(find.byType(OtpVerificationScreen), findsNothing);
  });

  testWidgets('hides the skip button when verification is mandatory', (tester) async {
    await pumpAuthScreen(
      tester,
      provider,
      const OtpVerificationScreen(phone: '20123456', allowSkip: false),
    );

    expect(find.text('Plus tard'), findsNothing);
  });

  testWidgets('an incomplete code is rejected inline and clears when the user types again', (tester) async {
    await pumpAuthScreen(tester, provider, const OtpVerificationScreen(phone: '20123456'));
    await tester.pumpAndSettle();

    await typeCode(tester, '123');
    await tapText(tester, 'Vérifier');
    await tester.pumpAndSettle();

    expect(find.text('Code à 6 chiffres'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    verifyNever(() => service.verifyPhoneOtp(any()));

    await typeCode(tester, '1234');
    await tester.pumpAndSettle();
    expect(find.text('Code à 6 chiffres'), findsNothing);
  });

  testWidgets('flags the registration flow as the last step', (tester) async {
    await pumpAuthScreen(tester, provider, const OtpVerificationScreen(phone: '20123456'));
    expect(find.textContaining('Dernière étape'), findsOneWidget);
  });

  testWidgets('shows no step badge when re-verifying from the profile', (tester) async {
    await pumpAuthScreen(
      tester,
      provider,
      const OtpVerificationScreen(phone: '20123456', allowSkip: false),
    );
    expect(find.textContaining('Dernière étape'), findsNothing);
  });

  testWidgets('the code field takes focus by itself once the code is sent', (tester) async {
    // Avant le correctif, `autofocus` était ignoré : le champ est désactivé
    // tant que le code n'est pas parti, donc le clavier ne s'ouvrait jamais seul.
    await pumpAuthScreen(
        tester, provider, const OtpVerificationScreen(phone: '92755660', resendDelay: Duration(seconds: 1)));
    await tester.pump(const Duration(seconds: 2));

    final field = tester.widget<EditableText>(
        find.descendant(of: find.byKey(const Key('otp-field')), matching: find.byType(EditableText)));
    expect(find.textContaining('Code envoyé au'), findsOneWidget); // le mock renvoie toujours +21620123456
    expect(field.focusNode.hasFocus, isTrue, reason: 'le clavier doit s\'ouvrir sans taper sur les cases');
  });

  group('UI contract (hero sheet)', () {
    // The visible boxes are the AnimatedContainers sized 46 x 56.
    Iterable<BoxDecoration> boxes(WidgetTester tester) => tester
        .widgetList<AnimatedContainer>(find.descendant(of: find.byType(OtpInput), matching: find.byType(AnimatedContainer)))
        .map((c) => c.decoration! as BoxDecoration);

    testWidgets('is a HeroSheetScaffold with an AuthHero and a primary PillButton', (tester) async {
      await pumpAuthScreen(tester, provider, const OtpVerificationScreen(phone: '20123456'));

      expect(find.byType(HeroSheetScaffold), findsOneWidget);
      expect(find.byType(AuthHero), findsOneWidget);
      expect(find.text('Vérification'), findsOneWidget);
      expect(tester.widget<PillButton>(find.widgetWithText(PillButton, 'Vérifier')).style, PillStyle.primary);
    });

    testWidgets('the code boxes are surfaceMuted with an outline border', (tester) async {
      await pumpAuthScreen(tester, provider, const OtpVerificationScreen(phone: '20123456'));
      await tester.pumpAndSettle();
      const tokens = AppTokens.light;

      final list = boxes(tester).toList();
      expect(list, hasLength(6));
      // Box 0 is the active one (primary border); the others are idle.
      expect(list.first.border!.top.color, tokens.primary);
      for (final b in list.skip(1)) {
        expect(b.color, tokens.surfaceMuted);
        expect(b.border!.top.color, tokens.outline);
      }
    });

    testWidgets('digits use textPrimary; a wrong code turns the boxes and digits danger', (tester) async {
      when(() => service.verifyPhoneOtp(any())).thenThrow(AuthFailure.fromCode('invalid-verification-code'));
      await pumpAuthScreen(tester, provider, const OtpVerificationScreen(phone: '20123456'));
      const tokens = AppTokens.light;

      await typeCode(tester, '12');
      expect(tester.widget<Text>(find.text('1')).style!.color, tokens.textPrimary);

      await typeCode(tester, '000000');
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text('0').first).style!.color, tokens.danger);
      for (final b in boxes(tester)) {
        expect(b.border!.top.color, tokens.danger);
      }
    });

    testWidgets('with the keyboard open the phone number is still shown in the sheet', (tester) async {
      await pumpAuthScreen(tester, provider, const OtpVerificationScreen(phone: '20123456'),
          size: const Size(360, 640), keyboardInset: 300);
      await tester.pumpAndSettle();

      expect(find.textContaining('+21620123456'), findsOneWidget);
      expect(find.textContaining('Dernière étape'), findsOneWidget);
    });

    for (final brightness in Brightness.values) {
      testWidgets('no text under 13 px in ${brightness.name}', (tester) async {
        await pumpAuthScreen(tester, provider, const OtpVerificationScreen(phone: '20123456'), brightness: brightness);
        await tester.pumpAndSettle();
        expectNoSmallText(tester);
      });
    }
  });
}
