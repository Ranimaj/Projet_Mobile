import 'package:campusconnect/screens/onboarding/onboarding_screen.dart';
import 'package:campusconnect/services/app_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/pump_themed.dart';

void main() {
  late AppPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await AppPrefs.load();
  });

  Future<void> pump(
    WidgetTester t, {
    VoidCallback? onStart,
    VoidCallback? onLogin,
    Brightness brightness = Brightness.light,
    Size size = const Size(420, 1000),
  }) =>
      pumpThemed(
        t,
        OnboardingScreen(prefs: prefs, onStart: onStart, onLogin: onLogin),
        brightness: brightness,
        size: size,
      );

  testWidgets('swiping reaches the second and third pages', (t) async {
    await pump(t);
    expect(find.textContaining('Toute la vie du campus'), findsOneWidget);
    await t.drag(find.byType(PageView), const Offset(-400, 0));
    await t.pumpAndSettle();
    expect(find.textContaining('Vends, donne'), findsOneWidget);
    await t.drag(find.byType(PageView), const Offset(-400, 0));
    await t.pumpAndSettle();
    expect(find.textContaining('Ne rate'), findsOneWidget);
  });

  testWidgets('Commencer marks onboarding seen then calls onStart', (t) async {
    var started = 0;
    await pump(t, onStart: () => started++);
    expect(prefs.onboardingSeen, isFalse);
    await t.tap(find.text('Commencer'));
    await t.pumpAndSettle();
    expect(prefs.onboardingSeen, isTrue);
    expect(started, 1);
  });

  testWidgets('the login link marks seen then calls onLogin', (t) async {
    var logins = 0;
    await pump(t, onLogin: () => logins++);
    await t.tap(find.textContaining('Se connecter'));
    await t.pumpAndSettle();
    expect(prefs.onboardingSeen, isTrue);
    expect(logins, 1);
  });

  for (final b in Brightness.values) {
    testWidgets('no small text at 360x640 (${b.name})', (t) async {
      await pump(t, brightness: b, size: const Size(360, 640));
      expectNoSmallText(t);
      expect(t.takeException(), isNull);
    });
  }
}
