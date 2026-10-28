import 'package:campusconnect/core/theme/app_theme.dart';
import 'package:campusconnect/core/theme/app_tokens.dart';
import 'package:campusconnect/widgets/social_icon_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, List<SocialIconItem> items, {String? caption}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: caption == null ? SocialIconRow(items: items) : SocialIconRow(items: items, caption: caption),
          ),
        ),
      ),
    );
  }

  testWidgets('renders the caption and one round 48 dp surface button per item with an outline', (tester) async {
    await pump(tester, [
      SocialIconItem(tooltip: 'Continuer avec Google', onPressed: () {}, child: const Text('G')),
      SocialIconItem(tooltip: 'Déverrouiller par biométrie', onPressed: () {}, icon: Icons.fingerprint_rounded),
    ]);
    const tokens = AppTokens.light;

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
      expect(m.color, tokens.surface);
      expect((m.shape! as CircleBorder).side.color, tokens.outline);
    }
    expect(tester.getSize(find.byTooltip('Continuer avec Google')).height, greaterThanOrEqualTo(48));
    expect(IconTheme.of(tester.element(find.byIcon(Icons.fingerprint_rounded))).color, tokens.textPrimary);
    expect(tester.widget<Text>(find.text('Ou connectez-vous avec')).style!.color, tokens.textSecondary);
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
