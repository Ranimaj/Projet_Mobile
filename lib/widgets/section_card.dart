import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

/// Panneau blanc arrondi, séparé du fond par la teinte seule (ni bordure ni
/// ombre), avec un titre de section en casse de phrase au-dessus — regroupe
/// les réglages / actions d'un écran (profil, paramètres...).
class SectionCard extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  const SectionCard({
    super.key,
    this.title,
    required this.children,
    this.padding = const EdgeInsets.symmetric(vertical: 6),
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              title!,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
          ),
        // Material (et non Container) : les ListTile dessinent leurs effets
        // d'encre sur le Material le plus proche.
        // Maquette : carte blanche arrondie (16 px) avec ombre douce.
        DecoratedBox(
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [AppColors.cardShadow]),
          child: Material(
            color: AppColors.surface,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: padding,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children),
            ),
          ),
        ),
      ],
    );
  }
}

/// Ligne d'action d'une [SectionCard] : icône, libellé, sous-titre optionnel
/// et chevron (ou widget de fin personnalisé). Pas de pastille autour de
/// l'icône, pas de filet entre les lignes : l'espace fait la séparation.
class SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? color;

  const SettingsTile({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final tint = color ?? AppColors.textPrimary;
    return ListTile(
      onTap: onTap,
      minVerticalPadding: 12,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
      leading: Icon(icon, size: 22, color: color ?? AppColors.primary),
      title: Text(
        label,
        style:
            TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: tint),
      ),
      subtitle: subtitle == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle!,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
            ),
      trailing: trailing ??
          (onTap == null
              ? null
              : const Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.textSecondary)),
    );
  }
}
