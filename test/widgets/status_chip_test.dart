import 'package:campusconnect/core/theme/app_tokens.dart';
import 'package:campusconnect/widgets/status_badge.dart';
import 'package:campusconnect/widgets/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_themed.dart';

void main() {
  Color fill(WidgetTester t) =>
      ((t.widget<Container>(find.byKey(const Key('chip-fill')))).decoration! as BoxDecoration).color!;
  Color text(WidgetTester t, String s) => t.widget<Text>(find.text(s)).style!.color!;

  for (final b in Brightness.values) {
    final tk = b == Brightness.dark ? AppTokens.dark : AppTokens.light;
    final cases = <StatusChipStyle, (Color, Color)>{
      StatusChipStyle.soft: (tk.primarySoft, tk.onPrimarySoft),
      StatusChipStyle.success: (tk.successSoft, tk.success),
      StatusChipStyle.warning: (tk.warningSoft, tk.warning),
      StatusChipStyle.danger: (tk.dangerSoft, tk.danger),
      StatusChipStyle.neutral: (tk.surfaceMuted, tk.textSecondary),
    };
    cases.forEach((style, colours) {
      testWidgets('StatusChip $style uses its soft/strong tokens ($b)', (t) async {
        await pumpThemed(t, StatusChip(label: 'Gratuit', style: style, icon: Icons.check), brightness: b);
        expect(fill(t), colours.$1);
        expect(text(t, 'Gratuit'), colours.$2);
        expect(t.widget<Icon>(find.byIcon(Icons.check)).color, colours.$2);
        expectNoSmallText(t);
      });
    });

    testWidgets('StatusChip onPhoto is white ($b)', (t) async {
      await pumpThemed(t, const StatusChip(label: 'Neuf', style: StatusChipStyle.onPhoto), brightness: b);
      expect(fill(t), Colors.white);
      expect(text(t, 'Neuf'), AppTokens.light.textPrimary);
    });
  }

  testWidgets('StatusBadge factories map to chip styles', (t) async {
    final expected = {
      StatusBadge.success('a'): (AppTokens.light.successSoft, AppTokens.light.success),
      StatusBadge.warning('a'): (AppTokens.light.warningSoft, AppTokens.light.warning),
      StatusBadge.info('a'): (AppTokens.light.surfaceMuted, AppTokens.light.textSecondary),
      StatusBadge.danger('a'): (AppTokens.light.dangerSoft, AppTokens.light.danger),
    };
    for (final e in expected.entries) {
      await pumpThemed(t, e.key);
      expect(fill(t), e.value.$1);
      expect(text(t, 'a'), e.value.$2);
    }
  });

  testWidgets('StatusBadge.info still builds (module compatibility)', (t) async {
    await pumpThemed(t, StatusBadge.info('Info'), brightness: Brightness.dark);
    expect(find.text('Info'), findsOneWidget);
  });

  testWidgets('StatusBadge explicit colours are honoured', (t) async {
    await pumpThemed(t, const StatusBadge(label: 'X', background: Colors.red, foreground: Colors.blue));
    expect(fill(t), Colors.red);
    expect(text(t, 'X'), Colors.blue);
  });
}
