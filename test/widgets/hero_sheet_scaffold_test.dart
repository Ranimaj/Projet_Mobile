import 'package:campusconnect/widgets/hero_sheet_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_themed.dart';

void main() {
  Widget scaffold({Widget? bottomBar}) => HeroSheetScaffold(
        hero: const ColoredBox(key: Key('hero'), color: Colors.red),
        heroLeading: const SizedBox(key: Key('lead'), width: 48, height: 48),
        heroActions: const [SizedBox(key: Key('act'), width: 48, height: 48)],
        bottomBar: bottomBar,
        children: const [SizedBox(key: Key('content'), height: 40)],
      );

  Future<void> pump(WidgetTester t, Size size,
          {double inset = 0, Widget? bar}) =>
      pumpThemed(
          t,
          Builder(
              builder: (context) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(viewInsets: EdgeInsets.only(bottom: inset)),
                    child: SizedBox(
                        width: size.width,
                        height: size.height,
                        child: scaffold(bottomBar: bar)),
                  )),
          size: size);

  testWidgets(
      'hero is 34% clamped to [200,320]: 420x1000 -> 320; 360x640 -> 217.6',
      (t) async {
    await pump(t, const Size(420, 1000));
    expect(t.getSize(find.byKey(const Key('hero'))).height, 320);
    await pump(t, const Size(360, 640));
    expect(
        t.getSize(find.byKey(const Key('hero'))).height, closeTo(217.6, 0.01));
  });

  testWidgets('hero shrinks to 120 when viewInsets.bottom > 0', (t) async {
    await pump(t, const Size(420, 1000), inset: 300);
    expect(t.getSize(find.byKey(const Key('hero'))).height, 120);
  });

  testWidgets('hero shrinks to 120 on short screens', (t) async {
    await pump(t, const Size(420, 500));
    expect(t.getSize(find.byKey(const Key('hero'))).height, 120);
  });

  testWidgets('centres content at 800 wide (content width == 720)', (t) async {
    await pump(t, const Size(800, 1280));
    // 720 max width minus 2 * 20 page padding
    expect(t.getSize(find.byKey(const Key('content'))).width, 680);
    expect(t.getTopLeft(find.byKey(const Key('content'))).dx, 60);
  });

  testWidgets('compact width: content spans width minus page padding',
      (t) async {
    await pump(t, const Size(420, 1000));
    expect(t.getSize(find.byKey(const Key('content'))).width, 380);
  });

  testWidgets('leading, actions and bottom bar are placed', (t) async {
    await pump(t, const Size(420, 1000),
        bar: const SizedBox(key: Key('bar'), height: 80));
    expect(t.getTopLeft(find.byKey(const Key('lead'))).dx, lessThan(30));
    expect(t.getTopRight(find.byKey(const Key('act'))).dx, greaterThan(390));
    expect(t.getBottomLeft(find.byKey(const Key('bar'))).dy, 984); // 16 dp bar padding
  });
}
