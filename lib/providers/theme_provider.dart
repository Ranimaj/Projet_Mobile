import 'package:flutter/material.dart';

import '../services/app_prefs.dart';

/// Mode de thème courant (clair / sombre / système), persisté via [AppPrefs].
class ThemeProvider extends ChangeNotifier {
  ThemeProvider(this._prefs) : _mode = _prefs.themeMode;

  final AppPrefs _prefs;
  ThemeMode _mode;

  ThemeMode get mode => _mode;

  Future<void> setMode(ThemeMode m) async {
    if (m == _mode) return;
    _mode = m;
    notifyListeners();
    await _prefs.setThemeMode(m);
  }
}
