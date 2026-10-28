import 'package:campusconnect/core/utils/auth_failure.dart';
import 'package:campusconnect/core/theme/app_tokens.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/widgets/auth/auth_hero.dart';
import 'package:campusconnect/widgets/hero_sheet_scaffold.dart';
import 'package:campusconnect/widgets/pill_button.dart';
import 'package:campusconnect/screens/auth/forgot_password_screen.dart';
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
    provider = AuthProvider(authService: service);
  });

  tearDown(() => provider.dispose());

  testWidgets('validates the email before calling the service', (tester) async {
    await pumpAuthScreen(tester, provider, const ForgotPasswordScreen());

    await tapText(tester, 'Envoyer le lien');
    await tester.pump();
    expect(find.text('Email requis'), findsOneWidget);

    await enterField(tester, 0, 'nope');
    await tapText(tester, 'Envoyer le lien');
    await tester.pump();
    expect(find.text('Email invalide'), findsOneWidget);

    verifyNever(() => service.sendPasswordReset(any()));
  });

  testWidgets('shows the confirmation state after sending', (tester) async {
    when(() => service.sendPasswordReset(any())).thenAnswer((_) async {});
    await pumpAuthScreen(tester, provider, const ForgotPasswordScreen());

    await enterField(tester, 0, ' Amel@Esprit.tn ');
    await tapText(tester, 'Envoyer le lien');
    await tester.pumpAndSettle();

    verify(() => service.sendPasswordReset(' Amel@Esprit.tn ')).called(1);
    expect(find.textContaining('amel@esprit.tn'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });

  testWidgets('does not reveal that an account does not exist', (tester) async {
    when(() => service.sendPasswordReset(any())).thenThrow(AuthFailure.fromCode('user-not-found'));
    await pumpAuthScreen(tester, provider, const ForgotPasswordScreen());

    await enterField(tester, 0, 'ghost@esprit.tn');
    await tapText(tester, 'Envoyer le lien');
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(find.text('Aucun compte avec cet email.'), findsNothing);
  });

  testWidgets('shows other errors in a snackbar and stays on the form', (tester) async {
    when(() => service.sendPasswordReset(any())).thenThrow(AuthFailure.fromCode('network-request-failed'));
    await pumpAuthScreen(tester, provider, const ForgotPasswordScreen());

    await enterField(tester, 0, 'amel@esprit.tn');
    await tapText(tester, 'Envoyer le lien');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Pas de connexion réseau.'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
  });

  testWidgets('prefills the email and lets the user pick another address', (tester) async {
    when(() => service.sendPasswordReset(any())).thenAnswer((_) async {});
    await pumpAuthScreen(tester, provider, const ForgotPasswordScreen(initialEmail: 'amel@esprit.tn'));

    expect(find.widgetWithText(TextFormField, 'amel@esprit.tn'), findsOneWidget);

    await tapText(tester, 'Envoyer le lien');
    await tester.pumpAndSettle();
    await tapText(tester, 'Utiliser une autre adresse');
    await tester.pumpAndSettle();

    expect(find.text('Envoyer le lien'), findsOneWidget);
  });

  testWidgets('the confirmation names the address and offers a way back', (tester) async {
    when(() => service.sendPasswordReset(any())).thenAnswer((_) async {});
    await pumpAuthScreen(tester, provider, const ForgotPasswordScreen(initialEmail: 'Amel@Esprit.tn'));

    await tapText(tester, 'Envoyer le lien');
    await tester.pumpAndSettle();

    expect(find.text('Lien envoyé'), findsOneWidget);
    expect(find.textContaining('amel@esprit.tn', findRichText: true), findsOneWidget);
    expect(find.text('Retour à la connexion'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('a network error can be dismissed and the form stays usable', (tester) async {
    when(() => service.sendPasswordReset(any())).thenThrow(AuthFailure.fromCode('network-request-failed'));
    await pumpAuthScreen(tester, provider, const ForgotPasswordScreen(initialEmail: 'amel@esprit.tn'));

    await tapText(tester, 'Envoyer le lien');
    await tester.pumpAndSettle();
    expect(find.text('Pas de connexion réseau.'), findsOneWidget);

    await tester.tap(find.byTooltip('Fermer'));
    await tester.pumpAndSettle();

    expect(find.text('Pas de connexion réseau.'), findsNothing);
    expect(find.text('Envoyer le lien'), findsOneWidget);
  });

  group('UI contract (hero sheet)', () {
    testWidgets('is a HeroSheetScaffold with an AuthHero and a primary PillButton', (tester) async {
      await pumpAuthScreen(tester, provider, const ForgotPasswordScreen());

      expect(find.byType(HeroSheetScaffold), findsOneWidget);
      expect(find.byType(AuthHero), findsOneWidget);
      expect(find.text('Mot de passe oublié'), findsOneWidget);
      expect(tester.widget<PillButton>(find.widgetWithText(PillButton, 'Envoyer le lien')).style, PillStyle.primary);
    });

    testWidgets('the sent state keeps the hero, shows the success mark in the success token', (tester) async {
      when(() => service.sendPasswordReset(any())).thenAnswer((_) async {});
      await pumpAuthScreen(tester, provider, const ForgotPasswordScreen(initialEmail: 'amel@esprit.tn'));
      await tapText(tester, 'Envoyer le lien');
      await tester.pumpAndSettle();

      expect(find.byType(AuthHero), findsOneWidget);
      expect(tester.widget<Icon>(find.byIcon(Icons.check_circle_rounded)).color, AppTokens.light.success);
    });

    testWidgets('a field error uses the danger token', (tester) async {
      await pumpAuthScreen(tester, provider, const ForgotPasswordScreen());
      await tapText(tester, 'Envoyer le lien');
      await tester.pump();
      expect(tester.widget<Text>(find.text('Email requis')).style!.color, AppTokens.light.danger);
    });

    for (final brightness in Brightness.values) {
      testWidgets('no text under 13 px in ${brightness.name}', (tester) async {
        await pumpAuthScreen(tester, provider, const ForgotPasswordScreen(), brightness: brightness);
        expectNoSmallText(tester);
      });
    }
  });
}
