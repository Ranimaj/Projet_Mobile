import 'package:flutter/material.dart';
import '../../core/constants/layout.dart';
import '../../core/theme/app_tokens.dart';

/// Hero of the auth screens: the token gradient, two translucent circles, an
/// icon tile at the top right and the title / subtitle at the bottom left.
///
/// It fills the hero slot of `HeroSheetScaffold`. When that slot is compact
/// (keyboard open or short screen) the tile and the subtitle are dropped and
/// the title moves clear of the back button, so nothing overlaps.
class AuthHero extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const AuthHero({super.key, required this.title, required this.subtitle, required this.icon});

  static const double _tileSize = 48;
  static const double _compactBelow = 200;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final media = MediaQuery.of(context);
    final textTheme = Theme.of(context).textTheme;
    final top = media.padding.top;
    final reduceMotion = media.disableAnimations;

    return DecoratedBox(
      decoration: BoxDecoration(gradient: t.heroGradient),
      child: LayoutBuilder(builder: (context, c) {
        final h = c.maxHeight;
        final compact = h < _compactBelow;
        final titleText = Text(
          title,
          maxLines: compact ? 1 : 2,
          overflow: compact ? TextOverflow.visible : TextOverflow.ellipsis,
          style: textTheme.headlineLarge?.copyWith(color: t.onPrimary),
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: -h * 0.3,
              right: -h * 0.25,
              child: _Circle(size: h * 0.8, color: t.onPrimary.withValues(alpha: 0.12)),
            ),
            Positioned(
              bottom: -h * 0.2,
              left: -h * 0.15,
              child: _Circle(size: h * 0.5, color: t.onPrimary.withValues(alpha: 0.08)),
            ),
            if (!compact)
              Positioned(
                top: top + 8,
                right: kPagePadding,
                child: Container(
                  width: _tileSize,
                  height: _tileSize,
                  decoration: BoxDecoration(
                    color: t.onPrimary.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: t.onPrimary, size: 24),
                ),
              ),
            if (compact)
              Positioned(
                top: top,
                bottom: 0,
                left: kPagePadding + _tileSize,
                right: kPagePadding,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: titleText),
                ),
              )
            else
              Positioned(
                left: kPagePadding,
                right: kPagePadding,
                // Clears the 28 dp the sheet pulls over the hero, plus a 16 dp margin.
                bottom: 28 + 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleText,
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 160),
                      child: Text(
                        subtitle,
                        key: ValueKey(subtitle),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyLarge?.copyWith(color: t.onPrimary.withValues(alpha: 0.85)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      }),
    );
  }
}

class _Circle extends StatelessWidget {
  final double size;
  final Color color;
  const _Circle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: color));
}
