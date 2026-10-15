import 'package:flutter/material.dart';

/// Palette officielle CampusConnect — reprise des maquettes de design.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF4F46E5);
  static const Color primary2 = Color(0xFF7C3AED);
  static const Color accent = Color(0xFFFB923C);
  static const Color accent2 = Color(0xFFF97316);
  static const Color success = Color(0xFF10B981);
  static const Color danger = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);

  static const Color background = Color(0xFFF7F7FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF1E1B2E);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color border = Color(0xFFECEBF3);

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, primary2],
  );

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4338CA), Color(0xFF6D28D9), Color(0xFFA21CAF)],
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
