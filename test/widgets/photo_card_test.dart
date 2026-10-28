import 'package:campusconnect/core/theme/app_tokens.dart';
import 'package:campusconnect/widgets/photo_card.dart';
import 'package:campusconnect/widgets/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_themed.dart';

void main() {
  for (final b in Brightness.values) {
    final tokens = b == Brightness.dark ? AppTokens.dark : AppTokens.light;
    testWidgets('PhotoCard without url shows the soft placeholder ($b)',
        (t) async {
      await pumpThemed(
          t,
          const PhotoCard(
              title: 'Vélo', width: 160, placeholderIcon: Icons.pedal_bike),
          brightness: b);
      final box =
          t.widget<Container>(find.byKey(const Key('photo-placeholder')));
      expect((box.decoration! as BoxDecoration).color, tokens.primarySoft);
      final icon = t.widget<Icon>(find.byIcon(Icons.pedal_bike));
      expect(icon.color, tokens.primary);
      expect(find.text('Vélo'), findsOneWidget);
      expectNoSmallText(t);
    });
  }

  testWidgets('PhotoCard heart toggles via onHeart and reflects favorite',
      (t) async {
    var fav = false;
    late StateSetter set;
    await pumpThemed(t, StatefulBuilder(builder: (context, setState) {
      set = setState;
      return PhotoCard(
          title: 'Vélo',
          width: 160,
          showHeart: true,
          favorite: fav,
          onHeart: () => set(() => fav = !fav),
          chip: const StatusChip(label: 'Gratuit'));
    }));
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    expect(find.text('Gratuit'), findsOneWidget);
    await t.tap(find.byIcon(Icons.favorite_border_rounded));
    await t.pump();
    expect(fav, isTrue);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expectTapTargets(t);
  });

  testWidgets('PhotoCard calls onTap', (t) async {
    var taps = 0;
    await pumpThemed(
        t, PhotoCard(title: 'Vélo', width: 160, onTap: () => taps++));
    await t.tap(find.text('Vélo'));
    expect(taps, 1);
  });
}
