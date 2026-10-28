import 'package:campusconnect/core/theme/app_tokens.dart';
import 'package:campusconnect/widgets/initials_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_themed.dart';

void main() {
  for (final b in Brightness.values) {
    final tk = b == Brightness.dark ? AppTokens.dark : AppTokens.light;

    testWidgets('shows white initials on primary ($b)', (t) async {
      await pumpThemed(t, const InitialsAvatar(initials: 'JK'), brightness: b);
      expect(t.widget<Text>(find.text('JK')).style!.color, Colors.white);
      final c = t.widget<Container>(find.ancestor(of: find.text('JK'), matching: find.byType(Container)).first);
      expect((c.decoration! as BoxDecoration).color, tk.primary);
      expectNoSmallText(t);
    });

    testWidgets('InitialsAvatar verified shows the check badge ($b)', (t) async {
      await pumpThemed(t, const InitialsAvatar(initials: 'JK', verified: true), brightness: b);
      expect(find.byKey(const Key('verified-badge')), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    testWidgets('tappable avatar has a 48 dp target ($b)', (t) async {
      var taps = 0;
      await pumpThemed(t, InitialsAvatar(initials: 'JK', onTap: () => taps++), brightness: b);
      expectTapTargets(t);
      await t.tap(find.text('JK'));
      expect(taps, 1);
    });
  }

  testWidgets('no badge when not verified', (t) async {
    await pumpThemed(t, const InitialsAvatar(initials: 'JK'));
    expect(find.byKey(const Key('verified-badge')), findsNothing);
  });
}
