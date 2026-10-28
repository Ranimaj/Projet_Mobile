import 'package:campusconnect/widgets/featured_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_themed.dart';

void main() {
  testWidgets('FeaturedCard shows chip, title, meta and calls onAction',
      (t) async {
    var actions = 0;
    var taps = 0;
    await pumpThemed(
        t,
        FeaturedCard(
          chipLabel: 'À la une',
          title: 'Soirée de rentrée',
          meta: const [
            FeaturedMeta(Icons.event, '12 oct.'),
            FeaturedMeta(Icons.place, 'Campus'),
          ],
          actionLabel: "S'inscrire",
          onAction: () => actions++,
          onTap: () => taps++,
        ));
    expect(find.text('À la une'), findsOneWidget);
    expect(find.text('Soirée de rentrée'), findsOneWidget);
    expect(find.text('12 oct.'), findsOneWidget);
    expect(find.text('Campus'), findsOneWidget);
    expect(find.byIcon(Icons.event), findsOneWidget);
    expect(t.widget<Text>(find.text('Soirée de rentrée')).style!.color,
        Colors.white);
    expectNoSmallText(t);
    await t.tap(find.text("S'inscrire"));
    expect(actions, 1);
    expect(taps, 0);
    await t.tap(find.text('Soirée de rentrée'));
    expect(taps, 1);
  });
}
