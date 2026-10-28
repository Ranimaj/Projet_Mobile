import 'package:campusconnect/core/theme/app_tokens.dart';
import 'package:campusconnect/widgets/round_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_themed.dart';

void main() {
  Color fill(WidgetTester t) =>
      ((t.widget<Container>(find.byKey(const Key('round-fill')))).decoration!
              as BoxDecoration)
          .color!;

  for (final b in Brightness.values) {
    final tokens = b == Brightness.dark ? AppTokens.dark : AppTokens.light;

    testWidgets('renders icon, no small text, 48 dp target ($b)', (t) async {
      var taps = 0;
      await pumpThemed(
          t,
          RoundIconButton(
              tooltip: 'Action', icon: Icons.share, onPressed: () => taps++),
          brightness: b);
      expect(find.byIcon(Icons.share), findsOneWidget);
      expectNoSmallText(t);
      expectTapTargets(t);
      await t.tap(find.byIcon(Icons.share));
      expect(taps, 1);
    });

    testWidgets('styles use tokens ($b)', (t) async {
      await pumpThemed(
          t,
          const RoundIconButton(
              tooltip: 'Action', icon: Icons.add, style: RoundButtonStyle.soft),
          brightness: b);
      expect(fill(t), tokens.primarySoft);
      await pumpThemed(
          t,
          const RoundIconButton(
              tooltip: 'Action',
              icon: Icons.add,
              style: RoundButtonStyle.primary),
          brightness: b);
      expect(fill(t), tokens.primary);
      await pumpThemed(
          t, const RoundIconButton(tooltip: 'Action', icon: Icons.add),
          brightness: b);
      expect(fill(t), tokens.surface);
    });

    testWidgets('RoundIconButton onPhoto is white ($b)', (t) async {
      await pumpThemed(
          t,
          RoundIconButton(
              tooltip: 'Action',
              icon: Icons.add,
              style: RoundButtonStyle.onPhoto,
              onPressed: () {}),
          brightness: b);
      expect(fill(t), Colors.white);
      expect(t.widget<Icon>(find.byIcon(Icons.add)).color,
          AppTokens.light.textPrimary);
    });

    testWidgets('showDot paints a primary dot ($b)', (t) async {
      await pumpThemed(
          t,
          const RoundIconButton(
              tooltip: 'Action', icon: Icons.notifications, showDot: true),
          brightness: b);
      final dot = t.widget<Container>(find.byKey(const Key('dot')));
      expect((dot.decoration! as BoxDecoration).color, tokens.primary);
    });
  }

  testWidgets('no dot by default', (t) async {
    await pumpThemed(
        t, const RoundIconButton(tooltip: 'Action', icon: Icons.add));
    expect(find.byKey(const Key('dot')), findsNothing);
  });

  testWidgets('disabled is muted and announced as disabled', (t) async {
    final handle = t.ensureSemantics();
    await pumpThemed(
        t, const RoundIconButton(tooltip: 'Partager', icon: Icons.add));
    expect(t.widget<Icon>(find.byIcon(Icons.add)).color,
        AppTokens.light.textSecondary);
    expect(
      t.getSemantics(find.bySemanticsLabel(RegExp('Partager|Retour'))),
      isSemantics(label: 'Partager', isButton: true, isEnabled: false),
    );
    handle.dispose();
  });

  testWidgets('semantics label equals the tooltip', (t) async {
    final handle = t.ensureSemantics();
    await pumpThemed(
        t,
        RoundIconButton(
            tooltip: 'Retour', icon: Icons.arrow_back, onPressed: () {}));
    expect(
      t.getSemantics(find.bySemanticsLabel(RegExp('Partager|Retour'))),
      isSemantics(
          label: 'Retour', isButton: true, isEnabled: true, hasTapAction: true),
    );
    handle.dispose();
  });
}
