import 'package:campusconnect/core/theme/app_tokens.dart';
import 'package:campusconnect/widgets/round_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_themed.dart';

void main() {
  Color fill(WidgetTester t) =>
      ((t.widget<Container>(find.byKey(const Key('round-fill')))).decoration! as BoxDecoration).color!;

  for (final b in Brightness.values) {
    final tokens = b == Brightness.dark ? AppTokens.dark : AppTokens.light;

    testWidgets('renders icon, no small text, 48 dp target ($b)', (t) async {
      var taps = 0;
      await pumpThemed(t, RoundIconButton(icon: Icons.share, onPressed: () => taps++), brightness: b);
      expect(find.byIcon(Icons.share), findsOneWidget);
      expectNoSmallText(t);
      expectTapTargets(t);
      await t.tap(find.byIcon(Icons.share));
      expect(taps, 1);
    });

    testWidgets('styles use tokens ($b)', (t) async {
      await pumpThemed(t, const RoundIconButton(icon: Icons.add, style: RoundButtonStyle.soft), brightness: b);
      expect(fill(t), tokens.primarySoft);
      await pumpThemed(t, const RoundIconButton(icon: Icons.add, style: RoundButtonStyle.primary), brightness: b);
      expect(fill(t), tokens.primary);
      await pumpThemed(t, const RoundIconButton(icon: Icons.add), brightness: b);
      expect(fill(t), tokens.surface);
    });

    testWidgets('RoundIconButton onPhoto is white ($b)', (t) async {
      await pumpThemed(t, RoundIconButton(icon: Icons.add, style: RoundButtonStyle.onPhoto, onPressed: () {}), brightness: b);
      expect(fill(t), Colors.white);
      expect(t.widget<Icon>(find.byIcon(Icons.add)).color, AppTokens.light.textPrimary);
    });

    testWidgets('showDot paints a primary dot ($b)', (t) async {
      await pumpThemed(t, const RoundIconButton(icon: Icons.notifications, showDot: true), brightness: b);
      final dot = t.widget<Container>(find.byKey(const Key('dot')));
      expect((dot.decoration! as BoxDecoration).color, tokens.primary);
    });
  }

  testWidgets('no dot by default and disabled ignores taps', (t) async {
    await pumpThemed(t, const RoundIconButton(icon: Icons.add));
    expect(find.byKey(const Key('dot')), findsNothing);
    await t.tap(find.byIcon(Icons.add));
    expect(t.takeException(), isNull);
  });
}
