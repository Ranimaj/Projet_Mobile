import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Styles de texte des écrans d'authentification posés sur un champ de couleur
/// plein écran. Dérivés du [TextTheme] courant pour garder la famille de police
/// (Outfit pour les titres, Inter pour le texte).
///
/// Échelle volontairement courte : un très grand (titre), un courant (15),
/// un petit (13). Rien en dessous de 13 px, pas d'ombre portée sur le texte.
class AuthTextStyles {
  AuthTextStyles._();

  static TextStyle title(BuildContext context) =>
      (Theme.of(context).textTheme.displayLarge ?? const TextStyle()).copyWith(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        height: 1.05,
        letterSpacing: -0.5,
      );

  static TextStyle subtitle(BuildContext context) =>
      (Theme.of(context).textTheme.bodyLarge ?? const TextStyle()).copyWith(
        fontSize: 15,
        height: 1.4,
        color: Colors.white.withValues(alpha: 0.85),
      );

  /// Texte saisi dans les champs soulignés.
  static const TextStyle input = TextStyle(color: Colors.white, fontSize: 15);

  static TextStyle hint = TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 15);

  static TextStyle helper = TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13);

  static const TextStyle fieldError =
      TextStyle(color: AppColors.authErrorOnGradient, fontSize: 13, fontWeight: FontWeight.w500);

  /// Petits libellés (case à cocher, liens secondaires).
  static const TextStyle small = TextStyle(color: Colors.white, fontSize: 13);

  static const TextStyle link = TextStyle(
    color: Colors.white,
    fontSize: 13,
    decoration: TextDecoration.underline,
    decorationColor: Colors.white,
  );

  static TextStyle caption = TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 15);

  static const TextStyle pillLabel =
      TextStyle(color: AppColors.authPillText, fontSize: 15, fontWeight: FontWeight.w600);

  static const TextStyle footer = TextStyle(color: Colors.white, fontSize: 14);

  static const TextStyle footerLink = TextStyle(
    color: Colors.white,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    decoration: TextDecoration.underline,
    decorationColor: Colors.white,
  );
}
