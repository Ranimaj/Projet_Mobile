import 'package:flutter/material.dart';
import '../core/theme/app_tokens.dart';

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
/// connexions alternatives (Google, biométrie…). Les ronds sont des boutons
/// `surface` de 48 dp minimum avec un contour `outline` (ombre en thème clair).
class SocialIconRow extends StatelessWidget {
  final String caption;
  final List<SocialIconItem> items;
  final double size;

  const SocialIconRow({
    super.key,
    this.caption = 'Ou connectez-vous avec',
    required this.items,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(caption, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
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
    final t = AppTokens.of(context);
    final enabled = item.onPressed != null;
    final light = Theme.of(context).brightness == Brightness.light;
    final fg = enabled ? t.textPrimary : t.textSecondary;
    return Tooltip(
      message: item.tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: item.tooltip,
        child: DecoratedBox(
          decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: light ? t.cardShadow : null),
          child: Material(
            color: t.surface,
            shape: CircleBorder(side: BorderSide(color: t.outline)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: item.onPressed,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: size,
                height: size,
                child: Center(
                  child: IconTheme(
                    data: IconThemeData(color: fg, size: 24),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(color: fg),
                      child: item.child ?? Icon(item.icon),
                    ),
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
