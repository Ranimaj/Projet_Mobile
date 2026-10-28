import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_tokens.dart';

enum PillStyle { primary, ghost, dark, danger }

/// Fully rounded 52 dp button. [PillStyle.dark] is meant for use on photos.
/// Shows a spinner while [isLoading]; disabled when [onPressed] is null.
class PillButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final PillStyle style;
  final bool isLoading;
  final IconData? icon;
  final bool expand;

  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.style = PillStyle.primary,
    this.isLoading = false,
    this.icon,
    this.expand = true,
  });

  @override
  State<PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<PillButton> {
  static const double _height = 52;
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.isLoading;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final disabled = widget.onPressed == null;

    final (fill, onFill) = switch (widget.style) {
      PillStyle.primary => (t.primary, Colors.white),
      PillStyle.ghost => (t.surface, t.primary),
      PillStyle.dark => (AppTokens.dark.surface, Colors.white),
      PillStyle.danger => (t.dangerSoft, t.danger),
    };
    final bg = disabled && widget.style != PillStyle.ghost ? t.surfaceMuted : fill;
    final fg = disabled ? t.textSecondary : onFill;
    final border = widget.style == PillStyle.ghost
        ? Border.all(color: disabled ? t.outline : t.primary, width: 1.5)
        : null;

    return Semantics(
      button: true,
      enabled: _enabled,
      child: AnimatedScale(
        scale: _pressed && _enabled && !reduceMotion ? 0.97 : 1,
        duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 110),
        child: Container(
          key: const Key('pill-fill'),
          width: widget.expand ? double.infinity : null,
          height: _height,
          constraints: const BoxConstraints(minWidth: 48),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(_height / 2), border: border),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const StadiumBorder(),
              splashColor: fg.withValues(alpha: 0.14),
              highlightColor: fg.withValues(alpha: 0.06),
              onTap: _enabled
                  ? () {
                      HapticFeedback.lightImpact();
                      widget.onPressed!();
                    }
                  : null,
              onTapDown: (_) => _setPressed(true),
              onTapUp: (_) => _setPressed(false),
              onTapCancel: () => _setPressed(false),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: AnimatedSwitcher(
                  duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 150),
                  child: widget.isLoading
                      ? Center(
                          key: const ValueKey('loading'),
                          widthFactor: 1,
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
                          ),
                        )
                      : Row(
                          key: const ValueKey('label'),
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (widget.icon != null) ...[
                              Icon(widget.icon, size: 18, color: fg),
                              const SizedBox(width: 8),
                            ],
                            Flexible(
                              child: Text(
                                widget.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge!
                                    .copyWith(color: fg, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
