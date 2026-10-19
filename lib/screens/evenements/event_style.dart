import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/event_model.dart';
import '../../widgets/status_badge.dart';
import 'event_categories.dart';
import 'event_rules.dart';

/// Couleurs, icônes et badges partagés par les écrans Événements.
/// La liste des catégories elle-même est dans event_categories.dart.
class EventStyle {
  EventStyle._();

  /// Couleur de la barre latérale des cartes, par catégorie (palette de la spec).
  static Color categoryColor(String category) {
    switch (category) {
      case EventCategories.conference:
        return AppColors.primary; // indigo
      case EventCategories.career:
        return AppColors.primary2; // violet
      case EventCategories.sport:
        return AppColors.success; // vert
      case EventCategories.culture:
        return AppColors.accent; // orange
      case EventCategories.studentLife:
        return AppColors.warning; // ambre
      default:
        return AppColors.textSecondary;
    }
  }

  /// Icône de la catégorie (en-tête du détail quand il n'y a pas d'affiche).
  static IconData categoryIcon(String category) {
    switch (category) {
      case EventCategories.conference:
        return Icons.mic_external_on_outlined;
      case EventCategories.career:
        return Icons.work_outline_rounded;
      case EventCategories.sport:
        return Icons.sports_soccer_outlined;
      case EventCategories.culture:
        return Icons.theater_comedy_outlined;
      case EventCategories.studentLife:
        return Icons.groups_outlined;
      default:
        return Icons.celebration_outlined;
    }
  }

  /// Badge de prix : « Gratuit » (vert) ou « 15 TND » (bleu). Informatif :
  /// aucun paiement dans l'app.
  static Widget priceBadge(EventModel event) => EventRules.isFree(event)
      ? StatusBadge.success(EventRules.priceLabel(event).toUpperCase())
      : StatusBadge.info(EventRules.priceLabel(event));

  /// Badges d'état calculés par statusAt (jamais stockés), « Inscrit » et prix.
  static List<Widget> badges(EventModel event, DateTime now, {required bool isRegistered}) {
    final status = event.statusAt(now);
    return [
      if (status == EventDisplayStatus.cancelled) StatusBadge.danger('ANNULÉ'),
      if (status == EventDisplayStatus.finished) StatusBadge.warning('TERMINÉ'),
      if (status == EventDisplayStatus.ongoing) StatusBadge.info('EN COURS'),
      if (status == EventDisplayStatus.full) StatusBadge.warning('COMPLET'),
      if (isRegistered && status != EventDisplayStatus.cancelled) StatusBadge.success('INSCRIT'),
      priceBadge(event),
    ];
  }
}
