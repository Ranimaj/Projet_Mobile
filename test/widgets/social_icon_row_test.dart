import 'package:campusconnect/core/theme/app_colors.dart';
import 'package:campusconnect/widgets/social_icon_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, List<SocialIconItem> items, {String? caption}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: AppColors.authGradientBottom,
          body: Center(
            child: caption == null ? SocialIconRow(items: items) : SocialIconRow(items: items, caption: caption),
          ),
        ),
      ),
    );
  }

  testWidgets('renders the caption and one flat round button per item (no outline)', (tester) async {
    await pump(tester, [
      SocialIconItem(tooltip: 'Continuer avec Google', onPressed: () {}, child: const Text('G')),
      SocialIconItem(tooltip: 'Déverrouiller par biométrie', onPressed: () {}, icon: Icons.fingerprint_rounded),
    ]);

    expect(find.text('Ou connectez-vous avec'), findsOneWidget);
    expect(find.byTooltip('Continuer avec Google'), findsOneWidget);
    expect(find.byTooltip('Déverrouiller par biométrie'), findsOneWidget);
    expect(find.text('G'), findsOneWidget);
    expect(find.byIcon(Icons.fingerprint_rounded), findsOneWidget);

    final materials = tester.widgetList<Material>(find.descendant(
      of: find.byType(SocialIconRow),
      matching: find.byWidgetPredicate((w) => w is Material && w.shape is CircleBorder),
    ));
    expect(materials, hasLength(2));
    for (final m in materials) {
      expect((m.shape! as CircleBorder).side, BorderSide.none, reason: 'aplat, pas de contour 1px');
      expect(m.color!.r, 1.0, reason: 'blanc translucide : un ton au-dessus du fond');
      expect(m.color!.a, closeTo(0.18, 0.01));
    }
    expect(tester.getSize(find.byTooltip('Continuer avec Google')).height, 56);
  });

  testWidgets('tapping an item calls its callback; a null callback is inert', (tester) async {
    var google = 0;
    await pump(tester, [
      SocialIconItem(tooltip: 'Continuer avec Google', onPressed: () => google++, child: const Text('G')),
      const SocialIconItem(tooltip: 'Indisponible', onPressed: null, icon: Icons.fingerprint_rounded),
    ]);

    await tester.tap(find.byTooltip('Continuer avec Google'));
    await tester.pump();
    expect(google, 1);

    await tester.tap(find.byTooltip('Indisponible'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a custom caption replaces the default one', (tester) async {
    await pump(tester, [SocialIconItem(tooltip: 'x', onPressed: () {}, icon: Icons.add)], caption: 'Autres options');
    expect(find.text('Autres options'), findsOneWidget);
    expect(find.text('Ou connectez-vous avec'), findsNothing);
  });

  testWidgets('items are exposed as labelled buttons', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, [
      SocialIconItem(tooltip: 'Continuer avec Google', onPressed: () {}, child: const Text('G')),
    ]);
    final node = tester.getSemantics(find.text('G'));
    expect(node, isSemantics(isButton: true, isEnabled: true, hasTapAction: true));
    expect(node.label, contains('Continuer avec Google'));
    handle.dispose();
  });
}
