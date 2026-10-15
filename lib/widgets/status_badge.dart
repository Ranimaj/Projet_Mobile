import 'package:flutter/material.dart';

/// Petit badge coloré de statut (Gratuit, Réservé, Inscrit, Vue, Accepté…)
/// réutilisé dans les 4 modules pour un langage visuel cohérent.
class StatusBadge extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const StatusBadge({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
  });

  factory StatusBadge.success(String label) => StatusBadge(
        label: label,
        background: const Color(0xFFD1FAE5),
        foreground: const Color(0xFF065F46),
      );

  factory StatusBadge.warning(String label) => StatusBadge(
        label: label,
        background: const Color(0xFFFEF3C7),
        foreground: const Color(0xFF92400E),
      );

  factory StatusBadge.info(String label) => StatusBadge(
        label: label,
        background: const Color(0xFFDBEAFE),
        foreground: const Color(0xFF1E40AF),
      );

  factory StatusBadge.danger(String label) => StatusBadge(
        label: label,
        background: const Color(0xFFFEE2E2),
        foreground: const Color(0xFF991B1B),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(10)),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: foreground),
      ),
    );
  }
}
