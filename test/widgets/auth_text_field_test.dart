import 'package:campusconnect/core/theme/app_tokens.dart';
import 'package:campusconnect/widgets/auth/auth_feedback.dart';
import 'package:campusconnect/widgets/auth/auth_text_field.dart';
import 'package:campusconnect/widgets/auth/password_strength_meter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_themed.dart';

void main() {
  late TextEditingController controller;

  setUp(() => controller = TextEditingController());
  tearDown(() => controller.dispose());

  Future<GlobalKey<FormState>> pump(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    bool isPassword = false,
    String? helper,
    String? Function(String?)? validator,
    ValueChanged<String>? onSubmitted,
  }) async {
    final formKey = GlobalKey<FormState>();
    await pumpThemed(
      tester,
      Form(
        key: formKey,
        child: AuthTextField(
          label: 'Email académique',
          icon: Icons.mail_outline_rounded,
          controller: controller,
          isPassword: isPassword,
          helper: helper,
          validator: validator,
          onSubmitted: onSubmitted,
        ),
      ),
      brightness: brightness,
    );
    return formKey;
  }

  InputDecorator decorator(WidgetTester tester) => tester.widget<InputDecorator>(find.byType(InputDecorator));

  for (final brightness in Brightness.values) {
    final tokens = brightness == Brightness.light ? AppTokens.light : AppTokens.dark;

    group('AuthTextField (${brightness.name})', () {
      testWidgets('is filled with surfaceMuted and has a radius of 14', (tester) async {
        await pump(tester, brightness: brightness);
        final d = decorator(tester);
        final theme = Theme.of(tester.element(find.byType(AuthTextField)));

        expect(theme.inputDecorationTheme.fillColor, tokens.surfaceMuted);
        expect(d.isFocused, isFalse);
        final border = theme.inputDecorationTheme.enabledBorder! as OutlineInputBorder;
        expect(border.borderRadius, BorderRadius.circular(14));
        expect(tester.widget<Icon>(find.byIcon(Icons.mail_outline_rounded)).color, tokens.textSecondary);
        expect(find.text('Email académique'), findsOneWidget);
      });

      testWidgets('a validation error is drawn in the danger token', (tester) async {
        final key = await pump(tester, brightness: brightness, validator: (_) => 'Champ invalide');
        key.currentState!.validate();
        await tester.pump();

        expect(tester.widget<Text>(find.text('Champ invalide')).style!.color, tokens.danger);
      });

      testWidgets('the password reveal toggles obscuring', (tester) async {
        await pump(tester, brightness: brightness, isPassword: true);
        EditableText editable() => tester.widget<EditableText>(find.byType(EditableText));

        expect(editable().obscureText, isTrue);
        await tester.tap(find.byTooltip('Afficher le mot de passe'));
        await tester.pump();
        expect(editable().obscureText, isFalse);
        expect(find.byTooltip('Masquer le mot de passe'), findsOneWidget);
      });

      testWidgets('shows the helper and submits through the keyboard', (tester) async {
        String? submitted;
        await pump(tester, brightness: brightness, helper: 'Aide', onSubmitted: (v) => submitted = v);
        expect(find.text('Aide'), findsOneWidget);

        await tester.enterText(find.byType(TextFormField), 'abc');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        expect(submitted, 'abc');
        expectNoSmallText(tester);
      });

      testWidgets('AuthErrorBanner renders on dangerSoft with danger text and a 48 dp close', (tester) async {
        var closed = false;
        await pumpThemed(
          tester,
          AuthErrorBanner(message: 'Oups', onClose: () => closed = true),
          brightness: brightness,
        );

        final box = tester.widget<Container>(find
            .ancestor(of: find.text('Oups'), matching: find.byType(Container))
            .first);
        expect((box.decoration! as BoxDecoration).color, tokens.dangerSoft);
        expect(tester.widget<Text>(find.text('Oups')).style!.color, tokens.danger);
        expect(tester.widget<Icon>(find.byIcon(Icons.error_outline_rounded)).color, tokens.danger);
        expect(tester.getSize(find.byTooltip('Fermer')).height, greaterThanOrEqualTo(48));

        await tester.tap(find.byTooltip('Fermer'));
        expect(closed, isTrue);
      });

      testWidgets('PasswordStrengthMeter fills its segments with danger / warning / success', (tester) async {
        Future<Set<Color?>> filled(String pw) async {
          await pumpThemed(tester, PasswordStrengthMeter(password: pw), brightness: brightness);
          final label = tester.widget<Text>(find.textContaining('Robustesse')).style!.color;
          expect(label, tokens.textSecondary);
          return tester
              .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
              .map((c) => (c.decoration! as BoxDecoration).color)
              .toSet()
            ..remove(tokens.outline);
        }

        expect(await filled('abc'), {tokens.danger});
        expect(await filled('abcdefg1'), {tokens.warning});
        expect(await filled('Abcdefg1!'), {tokens.success});
      });
    });
  }
}
