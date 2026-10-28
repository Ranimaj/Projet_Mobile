import 'package:campusconnect/core/theme/app_tokens.dart';
import 'package:campusconnect/widgets/filter_chip_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_themed.dart';

void main() {
  Color fill(WidgetTester t) =>
      ((t.widget<AnimatedContainer>(find.byKey(const Key('filter-fill')))).decoration! as BoxDecoration).color!;

  for (final b in Brightness.values) {
    final tk = b == Brightness.dark ? AppTokens.dark : AppTokens.light;

    testWidgets('FilterChipPill selected is primary with white label ($b)', (t) async {
      await pumpThemed(t, FilterChipPill(label: 'Livres', icon: Icons.book, selected: true, onTap: () {}), brightness: b);
      expect(fill(t), tk.primary);
      expect(t.widget<Text>(find.text('Livres')).style!.color, Colors.white);
      expectNoSmallText(t);
      expectTapTargets(t);
    });

    testWidgets('unselected uses surface and primary text colour ($b)', (t) async {
      await pumpThemed(t, FilterChipPill(label: 'Livres', selected: false, onTap: () {}), brightness: b);
      expect(fill(t), tk.surface);
      expect(t.widget<Text>(find.text('Livres')).style!.color, tk.textPrimary);
    });
  }

  testWidgets('tap calls onTap', (t) async {
    var taps = 0;
    await pumpThemed(t, FilterChipPill(label: 'Tous', selected: false, onTap: () => taps++));
    await t.tap(find.text('Tous'));
    expect(taps, 1);
  });
}
