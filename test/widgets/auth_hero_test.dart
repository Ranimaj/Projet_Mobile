import 'package:campusconnect/core/theme/app_tokens.dart';
import 'package:campusconnect/widgets/auth/auth_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_themed.dart';

void main() {
  Future<void> pump(WidgetTester t, {Brightness brightness = Brightness.light}) => pumpThemed(
        t,
        const SizedBox(
          height: 300,
          child: AuthHero(title: 'Bon retour', subtitle: 'Connecte-toi', icon: Icons.lock_open_rounded),
        ),
        brightness: brightness,
      );

  for (final brightness in Brightness.values) {
    final tokens = brightness == Brightness.light ? AppTokens.light : AppTokens.dark;

    group('AuthHero (${brightness.name})', () {
      testWidgets('renders title, subtitle and icon in onPrimary', (t) async {
        await pump(t, brightness: brightness);

        expect(find.text('Bon retour'), findsOneWidget);
        expect(find.text('Connecte-toi'), findsOneWidget);
        expect(t.widget<Text>(find.text('Bon retour')).style!.color, tokens.onPrimary);
        expect(t.widget<Text>(find.text('Connecte-toi')).style!.color, tokens.onPrimary.withValues(alpha: 0.85));
        expect(t.widget<Icon>(find.byIcon(Icons.lock_open_rounded)).color, tokens.onPrimary);
      });

      testWidgets('is painted with the hero gradient from the tokens', (t) async {
        await pump(t, brightness: brightness);

        final deco = t.widgetList<DecoratedBox>(find.descendant(
          of: find.byType(AuthHero),
          matching: find.byType(DecoratedBox),
        ));
        expect(deco.map((d) => (d.decoration as BoxDecoration).gradient), contains(tokens.heroGradient));
      });

      testWidgets('has no text under 13 px', (t) async {
        await pump(t, brightness: brightness);
        expectNoSmallText(t);
      });
    });
  }
}
