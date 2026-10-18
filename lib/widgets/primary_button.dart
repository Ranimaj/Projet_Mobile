import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_colors.dart';

/// Bouton principal — utilisé pour toutes les actions CTA (publier, postuler,
/// enregistrer…). Aplat d'une seule couleur, entièrement arrondi, sans ombre
/// ni dégradé ; léger rétrécissement à l'appui + vibration discrète, et fondu
/// entre le libellé et l'indicateur de chargement.
class PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  /// Couleur de fond (par défaut la couleur primaire).
  final Color color;

  /// Conservé pour compatibilité : seule la première couleur est utilisée, en
  /// aplat (plus de dégradé sur les boutons).
  final Gradient? gradient;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.color = AppColors.primary,
    this.gradient,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.isLoading;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  void _handleTap() {
    HapticFeedback.lightImpact();
    widget.onPressed?.call();
  }

  Color get _fill {
    final g = widget.gradient;
    if (g is LinearGradient && g.colors.isNotEmpty) return g.colors.first;
    return widget.color;
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final disabled = widget.onPressed == null;
    final fg = disabled ? AppColors.textSecondary : Colors.white;

    // Pas de `label` sur Semantics : le Text du libellé fournit déjà le sien.
    return Semantics(
      button: true,
      enabled: _enabled,
      child: AnimatedScale(
        scale: _pressed && _enabled && !reduceMotion ? 0.97 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 50),
          decoration: BoxDecoration(
            color: disabled ? AppColors.surfaceTone : _fill,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(25),
              splashColor: Colors.white.withValues(alpha: 0.18),
              highlightColor: Colors.white.withValues(alpha: 0.06),
              onTap: _enabled ? _handleTap : null,
              onTapDown: (_) => _setPressed(true),
              onTapUp: (_) => _setPressed(false),
              onTapCancel: () => _setPressed(false),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
                child: AnimatedSwitcher(
                  duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 150),
                  child: widget.isLoading
                      ? const Center(
                          key: ValueKey('loading'),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
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
                                style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 15),
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
