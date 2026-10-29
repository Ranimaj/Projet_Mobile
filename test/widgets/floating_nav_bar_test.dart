import 'package:campusconnect/core/theme/app_tokens.dart';
import 'package:campusconnect/widgets/floating_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_themed.dart';

const _items = [
  FloatingNavItem(icon: Icons.home_rounded, label: 'Accueil'),
  FloatingNavItem(icon: Icons.search_rounded, label: 'Explorer'),
  FloatingNavItem(icon: Icons.add_rounded, label: 'Publier'),
  FloatingNavItem(icon: Icons.chat_rounded, label: 'Messages'),
  FloatingNavItem(icon: Icons.person_rounded, label: 'Profil'),
];

void main() {
  Widget bar(int index, ValueChanged<int> on) => Align(
      alignment: Alignment.bottomCenter,
      child: FloatingNavBar(index: index, onChanged: on, items: _items));

  testWidgets('highlights index and calls onChanged; 5 semantics labels',
      (t) async {
    final handle = t.ensureSemantics();
    final taps = <int>[];
    await pumpThemed(t, bar(1, taps.add));
    final fills = t
        .widgetList<Container>(find.byKey(const Key('round-fill')))
        .map((c) => (c.decoration! as BoxDecoration).color)
        .toList();
    expect(fills[1], AppTokens.light.primary);
    expect(fills[0], isNot(AppTokens.light.primary));
    expect(fills.length, 5);
    for (final item in _items) {
      expect(find.bySemanticsLabel(item.label), findsOneWidget);
    }
    expect(
        t.getSemantics(find.bySemanticsLabel('Explorer')),
        isSemantics(
            label: 'Explorer',
            isButton: true,
            isSelected: true,
            isEnabled: true,
            hasTapAction: true));
    await t.tap(find.byIcon(Icons.person_rounded));
    expect(taps, [4]);
    expectTapTargets(t);
    handle.dispose();
  });

  testWidgets('never exceeds 480 wide at 800x1280', (t) async {
    await pumpThemed(t, bar(0, (_) {}), size: const Size(800, 1280));
    final w = t.getSize(find.byKey(const Key('nav-pill'))).width;
    expect(w, lessThanOrEqualTo(480));
    expect(t.getCenter(find.byKey(const Key('nav-pill'))).dx, 400);
  });

  testWidgets('fits at 360 wide and dark has outline border, no shadow',
      (t) async {
    await pumpThemed(t, bar(0, (_) {}),
        size: const Size(360, 640), brightness: Brightness.dark);
    final d = t.widget<Container>(find.byKey(const Key('nav-pill'))).decoration!
        as BoxDecoration;
    expect(d.boxShadow, isNull.or(isEmpty));
    expect((d.border! as Border).top.color, AppTokens.dark.outline);
    expect(t.getSize(find.byKey(const Key('nav-pill'))).width, 328);
  });
}

extension on Matcher {
  Matcher or(Matcher other) => anyOf(this, other);
}
