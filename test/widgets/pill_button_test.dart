import 'package:campusconnect/core/theme/app_tokens.dart';
import 'package:campusconnect/widgets/pill_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_themed.dart';

void main() {
  BoxDecoration decoration(WidgetTester t) =>
      t.widget<Container>(find.byKey(const Key('pill-fill'))).decoration! as BoxDecoration;
  Color labelColor(WidgetTester t, String s) => t.widget<Text>(find.text(s)).style!.color!;

  for (final b in Brightness.values) {
    final tk = b == Brightness.dark ? AppTokens.dark : AppTokens.light;

    testWidgets('primary is a 52 dp pill with white label on primary ($b)', (t) async {
      await pumpThemed(t, PillButton(label: 'Se connecter', icon: Icons.arrow_forward_rounded, onPressed: () {}), brightness: b);
      expect(t.getSize(find.byType(PillButton)).height, 52);
      final d = decoration(t);
      expect(d.color, tk.primary);
      expect(d.borderRadius, BorderRadius.circular(26));
      expect(labelColor(t, 'Se connecter'), Colors.white);
      expect(t.widget<Icon>(find.byIcon(Icons.arrow_forward_rounded)).color, Colors.white);
      expectNoSmallText(t);
      expectTapTargets(t);
    });

    testWidgets('PillButton ghost has primary border and text ($b)', (t) async {
      await pumpThemed(t, PillButton(label: 'Annuler', style: PillStyle.ghost, onPressed: () {}), brightness: b);
      final d = decoration(t);
      expect(d.color, tk.surface);
      final side = (d.border! as Border).top;
      expect(side.color, tk.primary);
      expect(side.width, 1.5);
      expect(labelColor(t, 'Annuler'), tk.primary);
    });

    testWidgets('danger uses dangerSoft and danger text ($b)', (t) async {
      await pumpThemed(t, PillButton(label: 'Supprimer', style: PillStyle.danger, onPressed: () {}), brightness: b);
      expect(decoration(t).color, tk.dangerSoft);
      expect(labelColor(t, 'Supprimer'), tk.danger);
    });

    testWidgets('dark is always the dark surface with white text ($b)', (t) async {
      await pumpThemed(t, PillButton(label: 'Voir', style: PillStyle.dark, onPressed: () {}), brightness: b);
      expect(decoration(t).color, AppTokens.dark.surface);
      expect(labelColor(t, 'Voir'), Colors.white);
    });
  }

  testWidgets('tapping calls onPressed once', (t) async {
    var taps = 0;
    await pumpThemed(t, PillButton(label: 'Go', onPressed: () => taps++));
    await t.tap(find.text('Go'));
    await t.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('PillButton loading hides label, shows spinner, ignores taps', (t) async {
    var taps = 0;
    await pumpThemed(t, PillButton(label: 'Go', isLoading: true, onPressed: () => taps++));
    await t.pump(const Duration(milliseconds: 200));
    expect(t.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator)).color, Colors.white);
    expect(find.text('Go'), findsNothing);
    await t.tap(find.byType(PillButton));
    await t.pump();
    expect(taps, 0);
  });

  testWidgets('disabled state is muted and does not react', (t) async {
    await pumpThemed(t, const PillButton(label: 'Go', onPressed: null));
    expect(decoration(t).color, AppTokens.light.surfaceMuted);
    expect(labelColor(t, 'Go'), AppTokens.light.textSecondary);
    await t.tap(find.text('Go'));
    await t.pump();
    expect(t.takeException(), isNull);
  });

  testWidgets('expand false shrinks to content; long labels never overflow', (t) async {
    await pumpThemed(t, PillButton(label: 'Go', expand: false, onPressed: () {}));
    expect(t.getSize(find.byType(PillButton)).width, lessThan(200));
    await pumpThemed(t, SizedBox(width: 120, child: PillButton(label: 'Un libellé vraiment très long', onPressed: () {})));
    expect(t.takeException(), isNull);
  });

  testWidgets('is announced as a button', (t) async {
    final handle = t.ensureSemantics();
    await pumpThemed(t, PillButton(label: 'Se connecter', onPressed: () {}));
    expect(
      t.getSemantics(find.text('Se connecter')),
      isSemantics(label: 'Se connecter', isButton: true, isEnabled: true, hasTapAction: true),
    );
    handle.dispose();
  });
}
