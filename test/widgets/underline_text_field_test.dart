import 'package:campusconnect/core/theme/app_colors.dart';
import 'package:campusconnect/widgets/underline_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TextEditingController controller;

  setUp(() => controller = TextEditingController());
  tearDown(() => controller.dispose());

  Future<GlobalKey<FormState>> pump(
    WidgetTester tester, {
    bool isPassword = false,
    String? helper,
    String? Function(String?)? validator,
    ValueChanged<String>? onSubmitted,
    FocusNode? focusNode,
  }) async {
    final formKey = GlobalKey<FormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: AppColors.authGradientBottom,
          body: Form(
            key: formKey,
            child: UnderlineTextField(
              hint: 'Email académique',
              icon: Icons.mail_outline_rounded,
              controller: controller,
              isPassword: isPassword,
              helper: helper,
              validator: validator,
              onSubmitted: onSubmitted,
              focusNode: focusNode,
            ),
          ),
        ),
      ),
    );
    return formKey;
  }

  TextField textField(WidgetTester tester) => tester.widget<TextField>(find.byType(TextField));

  testWidgets('has no filled box, a white icon, white hint and white underline borders', (tester) async {
    await pump(tester);
    final tf = textField(tester);
    final d = tf.decoration!;

    expect(d.filled, isFalse);
    expect(d.hintText, 'Email académique');
    expect(d.hintStyle!.color!.a, closeTo(0.8, 0.01));
    expect(d.hintStyle!.color!.r, 1.0);
    expect(tf.style!.color, Colors.white);
    expect(tf.cursorColor, Colors.white);
    expect(tester.widget<Icon>(find.byIcon(Icons.mail_outline_rounded)).color, Colors.white);

    final enabled = d.enabledBorder as UnderlineInputBorder;
    expect(enabled.borderSide.width, 1);
    expect(enabled.borderSide.color.a, closeTo(0.6, 0.01));

    final focused = d.focusedBorder as UnderlineInputBorder;
    expect(focused.borderSide.width, 2);
    expect(focused.borderSide.color, Colors.white);

    expect((d.errorBorder as UnderlineInputBorder).borderSide.color, AppColors.authErrorOnGradient);
    expect(d.errorStyle!.color, AppColors.authErrorOnGradient);
  });

  testWidgets('shows the helper text under the underline', (tester) async {
    await pump(tester, helper: 'Pour vérifier ton compte par SMS.');
    expect(find.text('Pour vérifier ton compte par SMS.'), findsOneWidget);
    expect(textField(tester).decoration!.helperStyle!.color!.r, 1.0);
  });

  testWidgets('validation errors are rendered in the on-gradient error colour', (tester) async {
    final formKey = await pump(tester, validator: (v) => (v == null || v.isEmpty) ? 'Email requis' : null);

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();

    final error = tester.widget<Text>(find.text('Email requis'));
    expect(error.style!.color, AppColors.authErrorOnGradient);

    await tester.enterText(find.byType(TextField), 'amel@esprit.tn');
    expect(formKey.currentState!.validate(), isTrue);
    expect(controller.text, 'amel@esprit.tn');
  });

  testWidgets('password fields are obscured and can be revealed with the white eye icon', (tester) async {
    await pump(tester, isPassword: true);

    EditableText editable() => tester.widget<EditableText>(find.byType(EditableText));
    expect(editable().obscureText, isTrue);
    expect(textField(tester).autocorrect, isFalse);

    final eye = find.byIcon(Icons.visibility_off_outlined);
    expect(tester.widget<Icon>(eye).color!.r, 1.0);
    await tester.tap(eye);
    await tester.pump();

    expect(editable().obscureText, isFalse);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    expect(find.byTooltip('Masquer le mot de passe'), findsOneWidget);
  });

  testWidgets('forwards the keyboard action to onSubmitted', (tester) async {
    String? submitted;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await pump(tester, onSubmitted: (v) => submitted = v, focusNode: focus);

    await tester.enterText(find.byType(TextField), 'secret123');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(submitted, 'secret123');
  });
}
