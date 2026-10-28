import 'package:campusconnect/services/app_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences raw;
  late AppPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    raw = await SharedPreferences.getInstance();
    prefs = AppPrefs(raw);
  });

  test('defaults: system mode, onboarding not seen', () {
    expect(prefs.themeMode, ThemeMode.system);
    expect(prefs.onboardingSeen, isFalse);
  });

  test('setThemeMode persists "dark" under theme_mode', () async {
    await prefs.setThemeMode(ThemeMode.dark);
    expect(raw.getString('theme_mode'), 'dark');
    expect(prefs.themeMode, ThemeMode.dark);
  });

  test('unknown theme_mode value falls back to system', () async {
    await raw.setString('theme_mode', 'bogus');
    expect(prefs.themeMode, ThemeMode.system);
  });

  test('setOnboardingSeen persists true', () async {
    await prefs.setOnboardingSeen();
    expect(raw.getBool('onboarding_seen'), isTrue);
    expect(prefs.onboardingSeen, isTrue);
  });

  test('biometricUnlock defaults to true and persists false', () async {
    expect(prefs.biometricUnlock, isTrue);
    await prefs.setBiometricUnlock(false);
    expect(raw.getBool('biometric_unlock'), isFalse);
    expect(prefs.biometricUnlock, isFalse);
  });

  test('load reads from SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'light'});
    final loaded = await AppPrefs.load();
    expect(loaded.themeMode, ThemeMode.light);
  });
}
