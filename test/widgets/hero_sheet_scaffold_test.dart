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
    expect(t.getBottomLeft(find.byKey(const Key('bar'))).dy,
        984); // 16 dp bar padding
  });

  testWidgets(
      'with keyboard open the last child scrolls above it and the bar is lifted',
      (t) async {
    await pumpThemed(
        t,
        Builder(
            builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(viewInsets: const EdgeInsets.only(bottom: 300)),
                  child: const SizedBox(
                    width: 360,
                    height: 640,
                    child: HeroSheetScaffold(
                      hero: ColoredBox(color: Colors.red),
                      bottomBar: SizedBox(key: Key('bar'), height: 80),
                      children: [
                        SizedBox(height: 600),
                        SizedBox(key: Key('last'), height: 40),
                      ],
                    ),
                  ),
                )),
        size: const Size(360, 640));
    await t.scrollUntilVisible(find.byKey(const Key('last')), 100,
        scrollable: find.byType(Scrollable));
    await t.ensureVisible(find.byKey(const Key('last')));
    await t.pump();
    expect(t.getBottomLeft(find.byKey(const Key('last'))).dy,
        lessThanOrEqualTo(640 - 300));
    expect(t.getBottomLeft(find.byKey(const Key('bar'))).dy,
        lessThanOrEqualTo(640 - 300));
  });

  testWidgets('heroOverlay straddles the sheet top edge at rest',
      (t) async {
    await pumpThemed(
        t,
        const SizedBox(
          width: 420,
          height: 1000,
          child: HeroSheetScaffold(
            hero: ColoredBox(key: Key('hero'), color: Colors.red),
            heroOverlay: SizedBox(key: Key('overlay'), width: 64, height: 64),
            children: [SizedBox(key: Key('content'), height: 40)],
          ),
        ),
        size: const Size(420, 1000));
    final heroBottom = t.getBottomLeft(find.byKey(const Key('hero'))).dy;
    final overlay = t.getRect(find.byKey(const Key('overlay')));
    final sheetTop = heroBottom - 28;
    expect(overlay.top, lessThan(sheetTop));
    expect(overlay.bottom, greaterThan(sheetTop));
    expect(overlay.left, 20);
  });

  Widget overlayScaffold({ScrollController? controller}) => HeroSheetScaffold(
        hero: const ColoredBox(key: Key('hero'), color: Colors.red),
        heroLeading: const SizedBox(key: Key('lead'), width: 48, height: 48),
        heroActions: const [SizedBox(key: Key('act'), width: 48, height: 48)],
        heroOverlay: GestureDetector(
          onTap: () {},
          child: const SizedBox(key: Key('overlay'), width: 72, height: 72),
        ),
        scrollController: controller,
        children: [
          for (var i = 0; i < 30; i++)
            SizedBox(key: Key('row-$i'), height: 60, child: Text('row $i')),
        ],
      );

  testWidgets('heroOverlay follows the list and fades out once scrolled',
      (t) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pumpThemed(
        t,
        SizedBox(
            width: 360,
            height: 640,
            child: overlayScaffold(controller: controller)),
        size: const Size(360, 640));
    final rest = t.getRect(find.byKey(const Key('overlay')));

    controller.jumpTo(20);
    await t.pump();
    final moved = t.getRect(find.byKey(const Key('overlay')));
    expect(moved.top, closeTo(rest.top - 20, 0.01));
    final opacity = t.widget<Opacity>(find.ancestor(
        of: find.byKey(const Key('overlay')), matching: find.byType(Opacity)));
    expect(opacity.opacity, lessThan(1));
    expect(
        t
            .widget<IgnorePointer>(find
                .ancestor(
                    of: find.byKey(const Key('overlay')),
                    matching: find.byType(IgnorePointer))
                .first)
            .ignoring,
        isTrue);

    controller.jumpTo(200);
    await t.pump();
    expect(find.byKey(const Key('overlay')), findsNothing);
  });

  for (final statusBar in [0.0, 24.0]) {
    testWidgets(
        'heroOverlay never covers the leading button on a 120 dp hero '
        '(status bar $statusBar)', (t) async {
      await pumpThemed(
          t,
          Builder(
              builder: (context) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        padding: EdgeInsets.only(top: statusBar),
                        viewInsets: const EdgeInsets.only(bottom: 300)),
                    child: SizedBox(
                        width: 360, height: 640, child: overlayScaffold()),
                  )),
          size: const Size(360, 640));
      expect(t.getSize(find.byKey(const Key('hero'))).height, 120);
      final lead = t.getRect(find.byKey(const Key('lead')));
      final overlay = find.byKey(const Key('overlay'));
      if (overlay.evaluate().isNotEmpty) {
        expect(t.getRect(overlay).overlaps(lead), isFalse);
      }
    });
  }
}
