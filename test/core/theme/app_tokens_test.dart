import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:campusconnect/core/theme/app_theme.dart';
import 'package:campusconnect/core/theme/app_tokens.dart';
import 'package:campusconnect/core/theme/contrast.dart';

void main() {
  for (final (name, t) in [('light', AppTokens.light), ('dark', AppTokens.dark)]) {
    test('$name body text pairs reach AA 4.5', () {
      expect(contrastRatio(t.textPrimary, t.background), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(t.textPrimary, t.surface), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(t.textSecondary, t.surface), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(t.onPrimarySoft, t.primarySoft), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(t.success, t.successSoft), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(t.warning, t.warningSoft), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(t.danger, t.dangerSoft), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(t.danger, t.surface), greaterThanOrEqualTo(4.5));
      expect(contrastRatio(t.warning, t.surface), greaterThanOrEqualTo(4.5));
    });
    test('$name white on primary reaches 3:1 (large bold text)',
        () => expect(contrastRatio(Colors.white, t.primary), greaterThanOrEqualTo(3)));
  }

  testWidgets('themes expose the tokens', (tester) async {
    var checked = false;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: Builder(builder: (c) {
        expect(AppTokens.of(c).background, AppTokens.dark.background);
        checked = true;
        return const SizedBox();
      }),
    ));
    expect(checked, isTrue);
  });

  test('light has shadows, dark has none', () {
    expect(AppTokens.light.cardShadow, isNotEmpty);
    expect(AppTokens.dark.cardShadow, isEmpty);
  });

  test('no text style in either theme is below 13 px', () {
    for (final (name, theme) in [('light', AppTheme.light), ('dark', AppTheme.dark)]) {
      final tt = theme.textTheme;
      for (final (style, s) in [
        ('displayLarge', tt.displayLarge), ('displayMedium', tt.displayMedium), ('displaySmall', tt.displaySmall),
        ('headlineLarge', tt.headlineLarge), ('headlineMedium', tt.headlineMedium), ('headlineSmall', tt.headlineSmall),
        ('titleLarge', tt.titleLarge), ('titleMedium', tt.titleMedium), ('titleSmall', tt.titleSmall),
        ('bodyLarge', tt.bodyLarge), ('bodyMedium', tt.bodyMedium), ('bodySmall', tt.bodySmall),
        ('labelLarge', tt.labelLarge), ('labelMedium', tt.labelMedium), ('labelSmall', tt.labelSmall),
      ]) {
        final size = s?.fontSize;
        if (size != null) {
          expect(size, greaterThanOrEqualTo(13), reason: '$name.$style is $size px');
        }
      }
    }
  });
}
