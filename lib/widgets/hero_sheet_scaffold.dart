import 'package:flutter/material.dart';
import '../core/constants/layout.dart';
import '../core/theme/app_tokens.dart';
import 'bottom_action_bar.dart';

/// Screen with a hero (photo or gradient) on top and a rounded white sheet
/// pulled over its bottom edge. The hero shrinks when the keyboard is open or
/// the screen is short. [children] scroll inside the sheet.
class HeroSheetScaffold extends StatelessWidget {
  final Widget hero;
  final Widget? heroLeading;
  final List<Widget> heroActions;
  final List<Widget> children;
  final Widget? bottomBar;
  final bool showHandle;
  final double heroFraction;
  final double minHeroHeight;
  final double maxHeroHeight;
  final double keyboardHeroHeight;

  /// Lets the first child poke up above the sheet's top edge (e.g. an avatar
  /// straddling the hero): the scrolling area is extended upward by this many
  /// dp while the children keep their natural position.
  final double contentLift;

  const HeroSheetScaffold({
    super.key,
    required this.hero,
    this.heroLeading,
    this.heroActions = const [],
    required this.children,
    this.bottomBar,
    this.showHandle = true,
    this.heroFraction = 0.34,
    this.minHeroHeight = 200,
    this.maxHeroHeight = 320,
    this.keyboardHeroHeight = 120,
    this.contentLift = 0,
  });

  static const double _overlap = 28;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final media = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: t.surface,
      resizeToAvoidBottomInset: false,
      body: LayoutBuilder(builder: (context, c) {
        final compactHeight = c.maxHeight < 560;
        final heroH = media.viewInsets.bottom > 0 || compactHeight
            ? keyboardHeroHeight
            : (c.maxHeight * heroFraction).clamp(minHeroHeight, maxHeroHeight);
        final wide = c.maxWidth > kCompactBreakpoint;
        final top = media.padding.top + 8;

        Widget content = ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(kPagePadding, contentLift, kPagePadding,
              (bottomBar == null ? 24 : 112) + media.viewInsets.bottom),
          children: children,
        );
        if (wide) {
          content = Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
              child: content,
            ),
          );
        }

        final sheet = Container(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(_overlap)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                if (showHandle)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Container(
                      key: const Key('sheet-handle'),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: t.handle,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  )
                else
                  const SizedBox(height: 16),
                Expanded(
                  child: contentLift == 0
                      ? content
                      : LayoutBuilder(
                          builder: (context, box) => Transform.translate(
                            offset: Offset(0, -contentLift),
                            child: OverflowBox(
                              alignment: Alignment.topCenter,
                              minHeight: 0,
                              maxHeight: box.maxHeight + contentLift,
                              child: SizedBox(
                                  height: box.maxHeight + contentLift,
                                  child: content),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        );

        return Stack(
          children: [
            Column(
              children: [
                SizedBox(height: heroH, width: double.infinity, child: hero),
                Expanded(
                  child: Transform.translate(
                    offset: const Offset(0, -_overlap),
                    child: OverflowBox(
                      alignment: Alignment.topCenter,
                      minHeight: 0,
                      maxHeight: c.maxHeight - heroH + _overlap,
                      child: SizedBox(
                          height: c.maxHeight - heroH + _overlap, child: sheet),
                    ),
                  ),
                ),
              ],
            ),
            if (heroLeading != null)
              Positioned(top: top, left: 12, child: heroLeading!),
            if (heroActions.isNotEmpty)
              Positioned(
                top: top,
                right: 12,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < heroActions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      heroActions[i],
                    ],
                  ],
                ),
              ),
            if (bottomBar != null)
              Positioned(
                left: 0,
                right: 0,
                // Lifted above the keyboard.
                bottom: media.viewInsets.bottom,
                child: BottomActionBar(child: bottomBar!),
              ),
          ],
        );
      }),
    );
  }
}
