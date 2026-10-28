import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_tokens.dart';

enum RoundButtonStyle { surface, soft, primary, onPhoto }

/// Round icon button (back, share, favourite…). The visual is [size] wide but
/// the touch area is always at least 48 dp. [showDot] adds a notification dot.
class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final RoundButtonStyle style;
  final double size;
  final String tooltip;
  final bool showDot;

  /// Overrides the fill colour and renders the button flat (no border, no
  /// shadow). Pass [Colors.transparent] for an inactive nav-bar item.
  final Color? background;

  const RoundIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.style = RoundButtonStyle.surface,
    this.size = 38,
    required this.tooltip,
    this.showDot = false,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final (styleFill, fg) = switch (style) {
      RoundButtonStyle.surface => (t.surface, t.textPrimary),
      RoundButtonStyle.soft => (t.primarySoft, t.primary),
      RoundButtonStyle.primary => (t.primary, Colors.white),
      RoundButtonStyle.onPhoto => (Colors.white, AppTokens.light.textPrimary),
    };
    final fill = background ?? styleFill;
    final raised = background == null && style == RoundButtonStyle.surface;
    final enabled = onPressed != null;
    final hit = size < 48 ? 48.0 : size;

    Widget button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled
          ? () {
              HapticFeedback.lightImpact();
              onPressed!();
            }
          : null,
      child: SizedBox(
        width: hit,
        height: hit,
        child: Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                key: const Key('round-fill'),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: fill,
                  shape: BoxShape.circle,
                  border: raised ? Border.all(color: t.outline) : null,
                  boxShadow: raised ? t.cardShadow : null,
                ),
                child: Icon(icon,
                    size: size * 0.5, color: enabled ? fg : t.textSecondary),
              ),
              if (showDot)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    key: const Key('dot'),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: t.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: fill, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        onTap: enabled ? onPressed : null,
        excludeSemantics: true,
        child: button,
      ),
    );
  }
}
