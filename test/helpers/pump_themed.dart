import 'package:campusconnect/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [child] inside a [MaterialApp] using the real light/dark themes, on a
/// fixed-size surface, centred on the theme background.
Future<void> pumpThemed(
  WidgetTester t,
  Widget child, {
  Brightness brightness = Brightness.light,
  Size size = const Size(420, 1000),
  double textScale = 1,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);

  await t.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: app!,
      ),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

/// Asserts that every [Text] on screen renders at 13 px or more. The effective
/// size comes from the widget's own style, falling back on the ambient
/// [DefaultTextStyle] when the style or its `fontSize` is null.
void expectNoSmallText(WidgetTester t) {
  for (final element in find.byType(Text).evaluate()) {
    final text = element.widget as Text;
    final size = text.style?.fontSize ?? DefaultTextStyle.of(element).style.fontSize ?? 14;
    expect(size, greaterThanOrEqualTo(13), reason: 'Text "${text.data}" is below 13 px');
  }
}

/// Asserts that every tappable (`InkWell` / `GestureDetector` with a non-null
/// `onTap`) offers a hit area of at least 48 x 48 dp.
///
/// The hit area is the widget's own rendered size, enlarged by any directly
/// enclosing `Padding`, `SizedBox` or `ConstrainedBox` (the usual way to pad a
/// small visual up to a touch target). Other ancestors (`Center`, layout
/// widgets) do not count.
void expectTapTargets(WidgetTester t) {
  final tappables = <Element>[
    ...find.byType(InkWell).evaluate().where((e) => (e.widget as InkWell).onTap != null),
    ...find.byType(GestureDetector).evaluate().where((e) => (e.widget as GestureDetector).onTap != null),
  ];
  for (final element in tappables) {
    var size = (element.renderObject! as RenderBox).size;
    var done = false;
    element.visitAncestorElements((ancestor) {
      if (done) return false;
      final w = ancestor.widget;
      if (w is Padding || w is SizedBox || w is ConstrainedBox) {
        final s = (ancestor.renderObject! as RenderBox).size;
        if (s.width > size.width) size = Size(s.width, size.height);
        if (s.height > size.height) size = Size(size.width, s.height);
        return true;
      }
      done = true;
      return false;
    });
    expect(size.width, greaterThanOrEqualTo(48), reason: '${element.widget.runtimeType} too narrow: $size');
    expect(size.height, greaterThanOrEqualTo(48), reason: '${element.widget.runtimeType} too short: $size');
  }
}
