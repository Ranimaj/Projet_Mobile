import 'package:campusconnect/providers/theme_provider.dart';
import 'package:campusconnect/services/app_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = AppPrefs(await SharedPreferences.getInstance());
  });

  test('starts from the persisted mode', () async {
    await prefs.setThemeMode(ThemeMode.light);
    expect(ThemeProvider(prefs).mode, ThemeMode.light);
  });

  test('ThemeProvider notifies and persists', () async {
    final p = ThemeProvider(prefs);
    var n = 0;
    p.addListener(() => n++);
    await p.setMode(ThemeMode.dark);
    expect(n, 1);
    expect(p.mode, ThemeMode.dark);
    expect(prefs.themeMode, ThemeMode.dark);
  });
}
