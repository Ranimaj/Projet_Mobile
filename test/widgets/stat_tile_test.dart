import 'package:campusconnect/core/theme/app_tokens.dart';
import 'package:campusconnect/widgets/stat_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_themed.dart';

void main() {
  for (final b in Brightness.values) {
    final tk = b == Brightness.dark ? AppTokens.dark : AppTokens.light;
    testWidgets('renders value and label on the surface ($b)', (t) async {
      await pumpThemed(t, const StatTile(value: '12', label: 'Annonces'), brightness: b);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('Annonces'), findsOneWidget);
      expect(t.widget<Text>(find.text('12')).style!.color, tk.textPrimary);
      expectNoSmallText(t);
    });
  }

  testWidgets('StatTile valueColor overrides', (t) async {
    await pumpThemed(t, const StatTile(value: '3', label: 'Points', valueColor: Colors.green));
    expect(t.widget<Text>(find.text('3')).style!.color, Colors.green);
  });
}
