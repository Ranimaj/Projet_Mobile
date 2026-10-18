import 'package:campusconnect/core/theme/app_colors.dart';
import 'package:campusconnect/widgets/gradient_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cercles décoratifs (Container rond) : il ne doit plus y en avoir.
final Finder circles = find.byWidgetPredicate(
  (w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).shape == BoxShape.circle,
);

void main() {
  Future<void> pump(WidgetTester tester, {Widget? child, bool pushed = false, Size size = const Size(420, 900)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final screen = GradientScaffold(
      title: 'Bon test !',
      subtitle: 'Sous-titre',
      icon: Icons.lock_open_rounded,
      child: child ?? const Text('BODY'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: pushed
            ? Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)),
                    child: const Text('open'),
                  ),
                ),
              )
            : screen,
      ),
    );
    if (pushed) {
      await tester.tap(find.text('open'));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('paints one full-screen purple gradient (maquette), no circles, no shadow', (tester) async {
    await pump(tester);

    final fields = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).where((b) {
      final d = b.decoration;
      return d is BoxDecoration && d.gradient == AppColors.brandGradient;
    });
    expect(fields, hasLength(1));
    expect((fields.single.decoration as BoxDecoration).boxShadow, isNull);
    expect(AppColors.brandGradient.colors, [const Color(0xFF4F46E5), const Color(0xFF7C3AED)]);

    // Le fond couvre tout l'écran même quand le contenu est court.
    final box = find.byWidgetPredicate(
        (w) => w is DecoratedBox && (w.decoration as BoxDecoration).gradient == AppColors.brandGradient);
    expect(tester.getSize(box), const Size(420, 900));
    expect(circles, findsNothing);
  });

  testWidgets('title and subtitle follow the gradient text styles', (tester) async {
    await pump(tester);

    final title = tester.widget<Text>(find.text('Bon test !')).style!;
    expect(title.fontSize, 34);
    expect(title.fontWeight, FontWeight.w700);
    expect(title.color, Colors.white);
    expect(title.shadows, anyOf(isNull, isEmpty), reason: 'pas d\'ombre portée sur le texte');

    final subtitle = tester.widget<Text>(find.text('Sous-titre')).style!;
    expect(subtitle.fontSize, 15);
    expect(subtitle.color!.a, closeTo(0.85, 0.01));
    expect(subtitle.color!.r, 1.0);

    expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget);
    expect(find.text('BODY'), findsOneWidget);
  });

  testWidgets('the title sits in the upper third of the screen', (tester) async {
    await pump(tester);
    final titleTop = tester.getTopLeft(find.text('Bon test !')).dy;
    expect(titleTop, lessThan(900 / 3));
  });

  testWidgets('shows the back button only when there is something to pop', (tester) async {
    await pump(tester);
    expect(find.byTooltip('Retour'), findsNothing);

    await pump(tester, pushed: true);
    expect(find.byTooltip('Retour'), findsOneWidget);
    final icon = tester.widget<Icon>(find.byIcon(Icons.arrow_back_rounded));
    expect(icon.color, Colors.white);

    await tester.tap(find.byTooltip('Retour'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(find.text('BODY'), findsNothing);
  });

  testWidgets('content is inside SafeArea + a scroll view, so tall forms stay reachable', (tester) async {
    await pump(
      tester,
      child: const Column(children: [SizedBox(height: 1500), Text('BOTTOM')]),
    );

    expect(find.byType(SafeArea), findsWidgets);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    await tester.ensureVisible(find.text('BOTTOM'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('BOTTOM')).bottom, lessThanOrEqualTo(900));
    expect(tester.takeException(), isNull);
  });

  testWidgets('content is capped at 440 px on wide screens', (tester) async {
    await pump(
      tester,
      size: const Size(1200, 900),
      child: const SizedBox(key: Key('fill'), width: double.infinity, height: 10),
    );
    expect(tester.getSize(find.byKey(const Key('fill'))).width, 440);
  });
}
