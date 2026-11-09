import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/screens/auth/forgot_password_screen.dart';
import 'package:campusconnect/services/auth_service.dart';
import 'package:campusconnect/widgets/auth/auth_hero.dart';
import 'package:campusconnect/widgets/hero_sheet_scaffold.dart';
import 'package:campusconnect/widgets/pill_button.dart';
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
    when(() => service.authStateChanges).thenAnswer((_) => const Stream<AuthAccount?>.empty());
    provider = AuthProvider(authService: service);
  });

  tearDown(() => provider.dispose());

  testWidgets('explains that an administrator resets the password, without any email form', (tester) async {
    await pumpAuthScreen(tester, provider, const ForgotPasswordScreen());

    expect(find.text('Mot de passe oublié'), findsOneWidget);
    expect(find.textContaining('administrateur'), findsWidgets);
    expect(find.textContaining('mot de passe provisoire'), findsOneWidget);
    expect(find.textContaining("pas d'email"), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Envoyer le lien'), findsNothing);
  });

  testWidgets('lists the three steps, ending with changing the temporary password', (tester) async {
    await pumpAuthScreen(tester, provider, const ForgotPasswordScreen());

    for (final step in ForgotPasswordScreen.steps) {
      expect(find.text(step), findsOneWidget);
    }
    expect(find.textContaining('Changer le mot de passe'), findsOneWidget);
  });

  testWidgets('recalls the email typed on the login screen, normalized', (tester) async {
    await pumpAuthScreen(tester, provider, const ForgotPasswordScreen(initialEmail: ' Amel@Esprit.tn '));

    expect(find.textContaining('amel@esprit.tn', findRichText: true), findsOneWidget);
  });

  testWidgets('does not recall an empty or invalid email', (tester) async {
    await pumpAuthScreen(tester, provider, const ForgotPasswordScreen(initialEmail: 'amel'));

    expect(find.textContaining('Ton compte', findRichText: true), findsNothing);
  });

  testWidgets('"Retour à la connexion" closes the screen', (tester) async {
    await pumpAuthScreen(tester, provider, const ForgotPasswordScreen());

    await tapText(tester, 'Retour à la connexion');
    await tester.pumpAndSettle();

    expect(find.byType(ForgotPasswordScreen), findsNothing);
  });

  testWidgets('the back button closes the screen', (tester) async {
    await pumpAuthScreen(tester, provider, const ForgotPasswordScreen());

    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();

    expect(find.byType(ForgotPasswordScreen), findsNothing);
  });

  testWidgets('with the keyboard-height hero, the explanation stays in the sheet', (tester) async {
    await pumpAuthScreen(tester, provider, const ForgotPasswordScreen(), size: const Size(360, 520));

    expect(find.text(ForgotPasswordScreen.subtitle), findsWidgets);
  });

  group('UI contract (hero sheet)', () {
    testWidgets('is a HeroSheetScaffold with an AuthHero and a primary PillButton', (tester) async {
      await pumpAuthScreen(tester, provider, const ForgotPasswordScreen());

      expect(find.byType(HeroSheetScaffold), findsOneWidget);
      expect(find.byType(AuthHero), findsOneWidget);
      expect(
        tester.widget<PillButton>(find.widgetWithText(PillButton, 'Retour à la connexion')).style,
        PillStyle.primary,
      );
    });

    for (final brightness in Brightness.values) {
      testWidgets('no text under 13 px in ${brightness.name}', (tester) async {
        await pumpAuthScreen(tester, provider, const ForgotPasswordScreen(initialEmail: 'amel@esprit.tn'),
            brightness: brightness);
        expectNoSmallText(tester);
      });
    }

    testWidgets('every tap target is at least 48 dp', (tester) async {
      await pumpAuthScreen(tester, provider, const ForgotPasswordScreen());
      expectTapTargets(tester);
    });
  });
}
