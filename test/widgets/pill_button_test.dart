import 'package:campusconnect/core/theme/app_colors.dart';
import 'package:campusconnect/widgets/pill_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget button, {double? constrainWidth}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: AppColors.authGradientBottom,
          body: Center(
            child: constrainWidth == null ? button : SizedBox(width: constrainWidth, child: button),
          ),
        ),
      ),
    );
  }

  BoxDecoration decoration(WidgetTester tester) {
    final container = tester.widget<Container>(find.descendant(
      of: find.byType(PillButton),
      matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration),
    ));
    return container.decoration! as BoxDecoration;
  }

  testWidgets('is a flat white 220×50 pill with blue label and arrow, and no resting shadow', (tester) async {
    await pump(tester, PillButton(label: 'Se connecter', icon: Icons.arrow_forward_rounded, onPressed: () {}));

    expect(tester.getSize(find.byType(PillButton)), const Size(220, 50));
    final d = decoration(tester);
    expect(d.color, Colors.white);
    expect(d.borderRadius, BorderRadius.circular(25), reason: 'entièrement arrondi (hauteur / 2)');
    expect(d.boxShadow, isNull, reason: 'pas d\'ombre sur un élément au repos');

    final label = tester.widget<Text>(find.text('Se connecter')).style!;
    expect(label.color, AppColors.authPillText);
    expect(label.fontWeight, FontWeight.w600);
    expect(tester.widget<Icon>(find.byIcon(Icons.arrow_forward_rounded)).color, AppColors.authPillText);
  });

  testWidgets('tapping calls onPressed once', (tester) async {
    var taps = 0;
    await pump(tester, PillButton(label: 'Go', onPressed: () => taps++));
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('loading shows a spinner in the same blue and ignores taps', (tester) async {
    var taps = 0;
    await pump(tester, PillButton(label: 'Go', isLoading: true, onPressed: () => taps++));
    await tester.pump(const Duration(milliseconds: 200));

    final spinner = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
    expect(spinner.color, AppColors.authPillText);
    expect(find.text('Go'), findsNothing);

    await tester.tap(find.byType(PillButton));
    await tester.pump();
    expect(taps, 0);
  });

  testWidgets('disabled state is dimmed and does not react', (tester) async {
    await pump(tester, const PillButton(label: 'Go', onPressed: null));
    expect(decoration(tester).color!.a, lessThan(1));
    await tester.tap(find.text('Go'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom size is honoured and long labels never overflow', (tester) async {
    await pump(tester, PillButton(label: 'Un libellé vraiment très long', width: 160, height: 44, onPressed: () {}));
    expect(tester.getSize(find.byType(PillButton)), const Size(160, 44));
    expect(decoration(tester).borderRadius, BorderRadius.circular(22));
    expect(tester.takeException(), isNull);
  });

  testWidgets('is announced as a button', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, PillButton(label: 'Se connecter', onPressed: () {}));
    expect(
      tester.getSemantics(find.text('Se connecter')),
      isSemantics(label: 'Se connecter', isButton: true, isEnabled: true, hasTapAction: true),
    );
    handle.dispose();
  });
}
