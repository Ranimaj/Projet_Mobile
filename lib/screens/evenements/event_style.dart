import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/event_model.dart';
import '../../widgets/status_badge.dart';

/// Couleurs et badges partagés par les écrans Événements.
class EventStyle {
  EventStyle._();

  /// Couleur de la barre latérale des cartes, par catégorie (palette de la spec).
  static Color categoryColor(String category) {
    switch (category) {
      case 'Conférence':
        return AppColors.primary;
      case 'Job Fair':
        return AppColors.primary2;
      case 'Sport':
        return AppColors.success;
      case 'Culture':
        return AppColors.accent;
      case 'Associatif':
        return AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }

  /// Icône de la catégorie (en-tête du détail quand il n'y a pas d'affiche).
  static IconData categoryIcon(String category) {
    switch (category) {
      case 'Conférence':
        return Icons.mic_external_on_outlined;
      case 'Job Fair':
        return Icons.work_outline_rounded;
      case 'Sport':
        return Icons.sports_soccer_outlined;
      case 'Culture':
        return Icons.theater_comedy_outlined;
      case 'Associatif':
        return Icons.groups_outlined;
      default:
        return Icons.celebration_outlined;
    }
  }

  /// Badges d'état calculés par statusAt (jamais stockés), plus « Inscrit ».
  static List<Widget> badges(EventModel event, DateTime now, {required bool isRegistered}) {
    final status = event.statusAt(now);
    return [
      if (status == EventDisplayStatus.cancelled) StatusBadge.danger('ANNULÉ'),
      if (status == EventDisplayStatus.finished) StatusBadge.warning('TERMINÉ'),
      if (status == EventDisplayStatus.ongoing) StatusBadge.info('EN COURS'),
      if (status == EventDisplayStatus.full) StatusBadge.warning('COMPLET'),
      if (isRegistered && status != EventDisplayStatus.cancelled) StatusBadge.success('INSCRIT'),
    ];
  }
}
