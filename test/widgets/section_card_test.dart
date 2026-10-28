import 'package:campusconnect/core/theme/app_tokens.dart';
import 'package:campusconnect/widgets/section_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_themed.dart';

void main() {
  testWidgets('SettingsTile(color) tints both icon and label', (t) async {
    final danger = AppTokens.light.danger;
    await pumpThemed(
        t,
        SectionCard(children: [
          SettingsTile(
              icon: Icons.delete,
              label: 'Supprimer',
              color: danger,
              onTap: () {}),
        ]));
    expect(t.widget<Icon>(find.byIcon(Icons.delete)).color, danger);
    expect(t.widget<Text>(find.text('Supprimer')).style!.color, danger);
  });
}
