import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Préférences utilisateur persistées (thème, onboarding, biométrie).
class AppPrefs {
  AppPrefs(this._prefs);

  final SharedPreferences _prefs;

  static const _themeModeKey = 'theme_mode';
  static const _onboardingSeenKey = 'onboarding_seen';
  static const _biometricUnlockKey = 'biometric_unlock';

  static Future<AppPrefs> load() async =>
      AppPrefs(await SharedPreferences.getInstance());

  ThemeMode get themeMode {
    final name = _prefs.getString(_themeModeKey);
    return ThemeMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> setThemeMode(ThemeMode m) =>
      _prefs.setString(_themeModeKey, m.name);

  bool get onboardingSeen => _prefs.getBool(_onboardingSeenKey) ?? false;

  Future<void> setOnboardingSeen() => _prefs.setBool(_onboardingSeenKey, true);

  bool get biometricUnlock => _prefs.getBool(_biometricUnlockKey) ?? true;

  Future<void> setBiometricUnlock(bool v) =>
      _prefs.setBool(_biometricUnlockKey, v);
}
