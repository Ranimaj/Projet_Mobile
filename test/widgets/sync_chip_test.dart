import 'package:campusconnect/core/theme/app_tokens.dart';
import 'package:campusconnect/widgets/sync_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_themed.dart';

void main() {
  Color fill(WidgetTester t) =>
      (t.widget<Container>(find.byKey(const Key('chip-fill'))).decoration!
              as BoxDecoration)
          .color!;

  testWidgets('SyncChip labels: À jour / 2 en attente / Hors ligne', (t) async {
    await pumpThemed(t, const SyncChip(online: true, pending: 0));
    expect(find.text('À jour'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    expect(fill(t), AppTokens.light.successSoft);

    await pumpThemed(t, const SyncChip(online: true, pending: 2));
    expect(find.text('2 en attente'), findsOneWidget);
    expect(find.byIcon(Icons.sync_rounded), findsOneWidget);
    expect(fill(t), AppTokens.light.warningSoft);

    await pumpThemed(t, const SyncChip(online: false, pending: 0));
    expect(find.text('Hors ligne'), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    expect(fill(t), AppTokens.light.warningSoft);

    await pumpThemed(t, const SyncChip(online: false, pending: 3));
    expect(find.text('Hors ligne'), findsOneWidget);
  });
}
