import 'package:flutter/material.dart';

/// Palette officielle CampusConnect — reprise des maquettes de design.
class AppColors {
  AppColors._();

  // Palette de la maquette : indigo profond, bleu vif et lavande.
  static const Color primary = Color(0xFF2B32B2);
  static const Color primary2 = Color(0xFF1483CA);
  static const Color lavender = Color(0xFF7C81CE);
  static const Color accent = Color(0xFFFB923C);
  static const Color accent2 = Color(0xFFF97316);
  static const Color success = Color(0xFF10B981);
  static const Color danger = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);

  static const Color background = Color(0xFFF4F5FC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1E1B2E);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color border = Color(0xFFE3E5F5);

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primary2],
  );

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2B32B2), Color(0xFF5A5FC4), Color(0xFF1483CA)],
  );

  /// Bandeau d'en-tête des écrans d'authentification (haut de page).
  static const LinearGradient authHeaderGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, lavender, primary2],
  );

  /// Surface « un ton au-dessus » du fond : panneaux et boutons tonals, sans
  /// bordure ni ombre (la séparation se fait par la teinte seule).
  static const Color surfaceTone = Color(0xFFE8EBF7);

  // --- Écrans d'authentification (connexion, inscription, OTP, mot de passe) --
  /// Champ de couleur plein écran : un seul bleu uni, encre blanche.
  static const Color authField = Color(0xFF3D7DD3);

  /// Conservés pour compatibilité : l'ancien dégradé n'est plus appliqué par
  /// défaut (règle « pas de dégradé » du guide de style).
  static const Color authGradientTop = Color(0xFF6EE0D9);
  static const Color authGradientBottom = authField;

  /// Texte du bouton pilule blanc posé sur le dégradé.
  static const Color authPillText = Color(0xFF2A3F9D);

  /// Messages d'erreur lisibles sur le dégradé.
  static const Color authErrorOnGradient = Color(0xFFFFE0E0);

  static const LinearGradient authScreenGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [authGradientTop, authGradientBottom],
  );

  // Les accents par module vivent dans theme/module_colors.dart.

  // --- Palette du cahier des charges (section 6) -------------------------------
  static const Color brandPrimary = Color(0xFF4F46E5);
  static const Color brandViolet = Color(0xFF7C3AED);
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandPrimary, brandViolet],
  );

  /// Annonce officielle (fond et bordure orangés de la maquette).
  static const Color officialTint = Color(0xFFFFF7ED);
  static const Color officialBorder = Color(0xFFFED7AA);
  static const Color officialInk = Color(0xFF9A3412);

  /// Puce « Gratuit » / statut positif.
  static const Color successTint = Color(0xFFD1FAE5);
  static const Color successInk = Color(0xFF065F46);

  /// Ombre douce des cartes (maquette : cartes arrondies 16–18 px).
  static const BoxShadow cardShadow = BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 4));

  /// Héro de l'accueil visiteur : dégradé diagonal indigo → bleu.
  static const Color heroStart = Color(0xFF2E3BB0);
  static const Color heroEnd = Color(0xFF3D7DD3);
  static const LinearGradient visitorHeroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [heroStart, heroEnd],
  );

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accent, accent2],
  );

  /// Couleurs de catégories (vente/don, annonces...) pour varier les vignettes.
  static const List<Color> categoryTints = [
    Color(0xFFC7D2FE),
    Color(0xFFFDE68A),
    Color(0xFFFBCFE8),
    Color(0xFFA7F3D0),
  ];
}
