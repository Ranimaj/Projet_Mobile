import 'package:flutter/material.dart';

/// Couleur d'accent de chaque module, réutilisable partout (accueil
/// visiteur, onglets, pastilles d'icônes…).
class ModuleColors {
  ModuleColors._();

  static const Color events = Color(0xFF5B6CF0);
  static const Color notices = Color(0xFFF59E0B);
  static const Color market = Color(0xFFEC4899);
  static const Color jobs = Color(0xFF10B981);

  /// Encre des grands chiffres sur carte blanche.
  static const Color countInk = Color(0xFF1A1A2E);

  // Variante « accueil connecté » (maquette HTML) : encre foncée + fond pastel.
  static const Color marketInk = Color(0xFFC2255C);
  static const Color marketSoft = Color(0xFFFCE7EF);
  static const Color noticesInk = Color(0xFFB4480A);
  static const Color noticesSoft = Color(0xFFFFEDD5);
  static const Color eventsInk = Color(0xFF3448C5);
  static const Color eventsSoft = Color(0xFFE6EBFD);
  static const Color jobsInk = Color(0xFF0B6B4D);
  static const Color jobsSoft = Color(0xFFDDF4EA);

  /// Opacité de la teinte derrière l'icône d'un module.
  static const double tileTintOpacity = 0.12;

  /// Teinte de fond d'une pastille d'icône pour [accent].
  static Color tint(Color accent) => accent.withValues(alpha: tileTintOpacity);
}
