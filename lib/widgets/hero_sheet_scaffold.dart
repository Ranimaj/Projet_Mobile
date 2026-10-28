import 'package:flutter/material.dart';
import '../core/constants/layout.dart';
import '../core/theme/app_tokens.dart';
import 'bottom_action_bar.dart';

/// Screen with a hero (photo or gradient) on top and a rounded white sheet
/// pulled over its bottom edge. The hero shrinks when the keyboard is open or
/// the screen is short. [children] scroll inside the sheet.
class HeroSheetScaffold extends StatefulWidget {
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

  /// Widget over the hero and the sheet, straddling the sheet's top edge
  /// (e.g. a profile avatar). At rest it sits [overlayTop] dp above the
  /// hero's bottom edge, aligned with the page padding. It follows the list
  /// when it scrolls and fades out within [overlayTop] dp of scrolling, so it
  /// never covers sheet rows; it is not built while it would collide with the
  /// hero buttons (short hero under the status bar).
  final Widget? heroOverlay;
  final double overlayTop;

  /// Controller of the sheet's list; one is created when null.
  final ScrollController? scrollController;

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
    this.heroOverlay,
    this.overlayTop = 52,
    this.scrollController,
  });

  @override
  State<HeroSheetScaffold> createState() => _HeroSheetScaffoldState();
}

class _HeroSheetScaffoldState extends State<HeroSheetScaffold> {
  static const double _overlap = 28;
  static const double _heroButtonSize = 48;

  ScrollController? _ownController;

  ScrollController get _controller =>
      widget.scrollController ?? (_ownController ??= ScrollController());

  @override
  void dispose() {
    _ownController?.dispose();
    super.dispose();
  }

  Widget _overlay(
      BuildContext context, double heroH, double left, double buttonsBottom) {
    final controller = _controller;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final offset = controller.hasClients && controller.positions.length == 1
            ? controller.offset.clamp(0.0, double.infinity)
            : 0.0;
        final y = heroH - widget.overlayTop - offset;
        final opacity = widget.overlayTop <= 0
            ? (offset > 0 ? 0.0 : 1.0)
            : (1 - offset / widget.overlayTop).clamp(0.0, 1.0);
        if (opacity == 0 || y < buttonsBottom) return const SizedBox.shrink();
        return Stack(
          children: [
            Positioned(
              top: y,
              left: left,
              child: IgnorePointer(
                ignoring: offset > 0,
                child: Opacity(opacity: opacity, child: child),
              ),
            ),
          ],
        );
      },
      child: widget.heroOverlay,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hero = widget.hero;
    final heroLeading = widget.heroLeading;
    final heroActions = widget.heroActions;
    final children = widget.children;
    final bottomBar = widget.bottomBar;
    final showHandle = widget.showHandle;
    final heroOverlay = widget.heroOverlay;
    final t = AppTokens.of(context);
    final media = MediaQuery.of(context);
    return Scaffold(
      backgroundColor: t.surface,
      resizeToAvoidBottomInset: false,
      body: LayoutBuilder(builder: (context, c) {
        final compactHeight = c.maxHeight < 560;
        final heroH = media.viewInsets.bottom > 0 || compactHeight
            ? widget.keyboardHeroHeight
            : (c.maxHeight * widget.heroFraction)
                .clamp(widget.minHeroHeight, widget.maxHeroHeight);
        final wide = c.maxWidth > kCompactBreakpoint;
        final top = media.padding.top + 8;

        Widget content = ListView(
          controller: _controller,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(kPagePadding, 0, kPagePadding,
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
                Expanded(child: content),
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
            if (heroOverlay != null)
              Positioned.fill(
                child: _overlay(
                  context,
                  heroH,
                  wide
                      ? (c.maxWidth - kContentMaxWidth) / 2 + kPagePadding
                      : kPagePadding,
                  heroLeading != null || heroActions.isNotEmpty
                      ? top + _heroButtonSize
                      : double.negativeInfinity,
                ),
              ),
            if (heroLeading != null)
              Positioned(top: top, left: 12, child: heroLeading),
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
                child: BottomActionBar(child: bottomBar),
              ),
          ],
        );
      }),
    );
  }
}
