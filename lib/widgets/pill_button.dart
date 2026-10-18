import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/auth_text_styles.dart';

/// Bouton « pilule » blanc (entièrement arrondi) posé sur un champ de couleur :
/// texte bleu, icône optionnelle, aplat sans ombre, spinner de la même couleur
/// en chargement, léger rétrécissement à l'appui.
class PillButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final double width;
  final double height;
  final Color background;
  final Color foreground;

  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.width = 220,
    this.height = 50,
    this.background = Colors.white,
    this.foreground = AppColors.authPillText,
  });

  @override
  State<PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<PillButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.isLoading;

  void _setPressed(bool v) {
    if (_pressed != v) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final disabled = widget.onPressed == null;
    final fg = disabled ? widget.foreground.withValues(alpha: 0.45) : widget.foreground;

    return Semantics(
      button: true,
      enabled: _enabled,
      child: AnimatedScale(
        scale: _pressed && _enabled && !reduceMotion ? 0.97 : 1,
        duration: const Duration(milliseconds: 110),
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: disabled ? widget.background.withValues(alpha: 0.7) : widget.background,
            borderRadius: BorderRadius.circular(widget.height / 2),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const StadiumBorder(),
              splashColor: widget.foreground.withValues(alpha: 0.12),
              highlightColor: widget.foreground.withValues(alpha: 0.05),
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
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: AnimatedSwitcher(
                  duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 150),
                  child: widget.isLoading
                      ? Center(
                          key: const ValueKey('loading'),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: widget.foreground),
                          ),
                        )
                      : Row(
                          key: const ValueKey('label'),
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
                                style: AuthTextStyles.pillLabel.copyWith(color: fg),
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
