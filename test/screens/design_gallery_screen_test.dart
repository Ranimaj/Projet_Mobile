import 'package:campusconnect/core/theme/app_theme.dart';
import 'package:campusconnect/providers/theme_provider.dart';
import 'package:campusconnect/screens/debug/design_gallery_screen.dart';
import 'package:campusconnect/services/app_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/pump_themed.dart';

void main() {
  for (final b in Brightness.values) {
    testWidgets('gallery renders without small text ($b)', (t) async {
      SharedPreferences.setMockInitialValues({});
      final provider = ThemeProvider(AppPrefs(await SharedPreferences.getInstance()));
      await pumpThemed(
        t,
        ChangeNotifierProvider<ThemeProvider>.value(value: provider, child: const DesignGalleryScreen()),
        brightness: b,
      );
      expect(find.text('Galerie du design'), findsOneWidget);
      expectNoSmallText(t);
    });
  }

  testWidgets('tapping Sombre sets ThemeMode.dark', (t) async {
    SharedPreferences.setMockInitialValues({});
    final provider = ThemeProvider(AppPrefs(await SharedPreferences.getInstance()));
    t.view.physicalSize = const Size(420, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(ChangeNotifierProvider<ThemeProvider>.value(
      value: provider,
      child: Consumer<ThemeProvider>(
        builder: (_, p, __) => MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: p.mode,
          home: const DesignGalleryScreen(),
        ),
      ),
    ));
    await t.tap(find.text('Sombre'));
    await t.pumpAndSettle();
    expect(provider.mode, ThemeMode.dark);
  });
}
