import 'package:campusconnect/core/theme/app_tokens.dart';
import 'package:campusconnect/widgets/search_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_themed.dart';

void main() {
  testWidgets('SearchPill shows hint, taps and filter callbacks', (t) async {
    var taps = 0, filters = 0;
    await pumpThemed(
        t,
        SearchPill(
            hint: 'Rechercher',
            onTap: () => taps++,
            onFilter: () => filters++));
    expect(find.text('Rechercher'), findsOneWidget);
    expectNoSmallText(t);
    expectTapTargets(t);
    await t.tap(find.text('Rechercher'));
    expect(taps, 1);
    await t.tap(find.byIcon(Icons.tune_rounded));
    expect(filters, 1);
  });

  testWidgets('SearchPill without onFilter has no filter button', (t) async {
    await pumpThemed(t, const SearchPill(hint: 'Rechercher'));
    expect(find.byIcon(Icons.tune_rounded), findsNothing);
    final box = t.widget<Container>(find.byKey(const Key('search-fill')));
    expect((box.decoration! as BoxDecoration).color, AppTokens.light.surface);
  });
}
