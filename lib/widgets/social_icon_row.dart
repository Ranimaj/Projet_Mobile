import 'package:flutter/material.dart';
import '../core/theme/auth_text_styles.dart';

/// Un bouton rond de [SocialIconRow] : [icon] ou [child] au choix, un
/// [tooltip] (aussi libellé d'accessibilité) et son action.
class SocialIconItem {
  final String tooltip;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? child;

  const SocialIconItem({required this.tooltip, required this.onPressed, this.icon, this.child})
      : assert(icon != null || child != null, 'icon ou child requis');
}

/// Légende (« Ou connectez-vous avec ») + rangée de boutons ronds pour les
/// connexions alternatives (Google, biométrie…). Les ronds sont des aplats
/// blancs translucides : un ton au-dessus du fond, sans contour ni ombre.
class SocialIconRow extends StatelessWidget {
  final String caption;
  final List<SocialIconItem> items;
  final double size;

  const SocialIconRow({
    super.key,
    this.caption = 'Ou connectez-vous avec',
    required this.items,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(caption, style: AuthTextStyles.caption, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: [for (final item in items) _RoundButton(item: item, size: size)],
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  final SocialIconItem item;
  final double size;
  const _RoundButton({required this.item, required this.size});

  @override
  Widget build(BuildContext context) {
    final enabled = item.onPressed != null;
    return Tooltip(
      message: item.tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: item.tooltip,
        child: Material(
          color: Colors.white.withValues(alpha: enabled ? 0.18 : 0.08),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: item.onPressed,
            customBorder: const CircleBorder(),
            splashColor: Colors.white.withValues(alpha: 0.25),
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: IconTheme(
                  data: IconThemeData(color: Colors.white.withValues(alpha: enabled ? 1 : 0.5), size: 24),
                  child: item.child ?? Icon(item.icon),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
