import 'dart:async';
import 'package:campusconnect/core/utils/auth_failure.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/screens/auth/otp_verification_screen.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';
import '../helpers/pump_app.dart';

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
}
