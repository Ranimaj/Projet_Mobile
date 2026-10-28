import 'package:campusconnect/core/theme/app_tokens.dart';
import 'package:campusconnect/widgets/setting_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_themed.dart';

void main() {
  for (final b in Brightness.values) {
    final tokens = b == Brightness.dark ? AppTokens.dark : AppTokens.light;
    testWidgets('SettingRow destructive uses danger colour ($b)', (t) async {
      await pumpThemed(
          t,
          SettingRow(
              icon: Icons.logout,
              title: 'Déconnexion',
              destructive: true,
              onTap: () {}),
          brightness: b);
      expect(t.widget<Icon>(find.byIcon(Icons.logout)).color, tokens.danger);
      expect(
          t.widget<Text>(find.text('Déconnexion')).style!.color, tokens.danger);
    });

    testWidgets('SettingRow normal uses tokens and chevron ($b)', (t) async {
      var taps = 0;
      await pumpThemed(
          t,
          SettingRow(
              icon: Icons.person,
              title: 'Profil',
              subtitle: 'Infos',
              onTap: () => taps++),
          brightness: b);
      expect(t.widget<Icon>(find.byIcon(Icons.person)).color, tokens.primary);
      expect(
          t.widget<Text>(find.text('Profil')).style!.color, tokens.textPrimary);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      expectNoSmallText(t);
      expectTapTargets(t);
      await t.tap(find.text('Profil'));
      expect(taps, 1);
    });
  }

  testWidgets('SettingRow trailing replaces chevron; no onTap no chevron',
      (t) async {
    await pumpThemed(
        t,
        SettingRow(
            icon: Icons.notifications,
            title: 'Notifications',
            trailing: Switch(value: true, onChanged: (_) {}),
            onTap: () {}));
    expect(find.byType(Switch), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);

    await pumpThemed(t, const SettingRow(icon: Icons.info, title: 'Version'));
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('SettingGroup shows title, muted container and dividers',
      (t) async {
    await pumpThemed(
        t,
        const SettingGroup(title: 'Compte', children: [
          SettingRow(icon: Icons.person, title: 'A'),
          SettingRow(icon: Icons.lock, title: 'B'),
          SettingRow(icon: Icons.info, title: 'C'),
        ]));
    expect(find.text('Compte'), findsOneWidget);
    final box = t.widget<Container>(find.byKey(const Key('group-fill')));
    expect(
        (box.decoration! as BoxDecoration).color, AppTokens.light.surfaceMuted);
    expect(find.byType(Divider), findsNWidgets(2));
  });
}
