import '../../models/event_model.dart';

/// Filtre principal de la liste des événements.
enum EventFilter { upcoming, past, myRegistrations, myEvents }

/// Règles métier du module Événements (addendum, section 4).
///
/// Fonctions pures, comme EventValidators : tout est passé en paramètre
/// (y compris « maintenant »), aucune dépendance à Firebase, donc testables.
/// Les règles Firestore appliquent les mêmes contrôles côté serveur.
class EventRules {
  EventRules._();

  /// Raison pour laquelle [userId] ne peut PAS s'inscrire, ou null.
  /// Ordre des contrôles : connecté, actif, pas terminé, pas commencé,
  /// pas déjà inscrit, places disponibles.
  static String? registrationBlocked(EventModel event, String? userId, DateTime now) {
    if (userId == null) return 'Connectez-vous pour vous inscrire.';
    if (event.status == EventStatus.cancelled) return 'Cet événement est annulé.';
    if (!now.isBefore(event.endDate)) return 'Cet événement est terminé.';
    // Comme dans firestore.rules (request.time < startDate) : les inscriptions
    // ferment au début de l'événement.
    if (!now.isBefore(event.startDate)) return "Les inscriptions sont closes : l'événement a commencé.";
    if (event.isUserRegistered(userId)) return 'Vous êtes déjà inscrit.';
    if (event.isFull) return 'Complet : plus aucune place disponible.';
    return null;
  }

  /// Raison pour laquelle [userId] ne peut PAS se désinscrire, ou null.
  /// Règle 4 : désinscription possible jusqu'au début de l'événement.
  static String? unregistrationBlocked(EventModel event, String? userId, DateTime now) {
    if (userId == null) return 'Connectez-vous pour vous désinscrire.';
    if (!event.isUserRegistered(userId)) return "Vous n'êtes pas inscrit.";
    if (event.status == EventStatus.cancelled) return 'Cet événement est annulé.';
    if (!now.isBefore(event.startDate)) return "Désinscription impossible : l'événement a commencé.";
    return null;
  }

  /// Deux créneaux se chevauchent si chacun commence avant la fin de l'autre.
  /// (Un événement qui finit à 16 h et un autre qui commence à 16 h : pas de conflit.)
  static bool overlaps(EventModel a, EventModel b) =>
      a.startDate.isBefore(b.endDate) && b.startDate.isBefore(a.endDate);

  /// Règle 3 : premier événement actif et non terminé où [userId] est déjà
  /// inscrit et qui chevauche [target], ou null.
  static EventModel? findConflict(EventModel target, List<EventModel> all, String userId, DateTime now) {
    for (final e in all) {
      if (e.id == target.id || !e.isUserRegistered(userId)) continue;
      if (e.status == EventStatus.cancelled || !now.isBefore(e.endDate)) continue;
      if (overlaps(e, target)) return e;
    }
    return null;
  }

  /// Règle 7 : l'organisateur ne peut pas supprimer un événement qui a des
  /// inscrits (il doit l'annuler) ; l'admin peut toujours (modération).
  static String? deleteBlocked(EventModel event, {required bool isAdmin}) {
    if (isAdmin || event.registeredUserIds.isEmpty) return null;
    final n = event.registeredUserIds.length;
    return "Impossible de supprimer : $n inscrit(s). Annulez plutôt l'événement.";
  }

  /// Règle 6 : on n'annule ni un événement déjà annulé, ni un événement terminé.
  static String? cancelBlocked(EventModel event, DateTime now) {
    if (event.status == EventStatus.cancelled) return 'Cet événement est déjà annulé.';
    if (!now.isBefore(event.endDate)) return 'Un événement terminé ne peut pas être annulé.';
    return null;
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// Règles 6, 8 et 12 : filtre principal + catégorie + jour, triés par date
  /// de début. Tous les filtres se combinent.
  /// - À venir : ni annulés, ni terminés (les événements en cours restent visibles).
  /// - Passés : terminés et non annulés (lecture seule).
  /// - Mes inscriptions / Mes événements : tout, y compris annulés et passés.
  static List<EventModel> filter(
    List<EventModel> all, {
    required EventFilter filter,
    required DateTime now,
    String? userId,
    String? category,
    DateTime? day,
  }) {
    bool matchesFilter(EventModel e) {
      switch (filter) {
        case EventFilter.upcoming:
          return e.status == EventStatus.active && now.isBefore(e.endDate);
        case EventFilter.past:
          return e.status == EventStatus.active && !now.isBefore(e.endDate);
        case EventFilter.myRegistrations:
          return userId != null && e.isUserRegistered(userId);
        case EventFilter.myEvents:
          return userId != null && e.organizerId == userId;
      }
    }

    final list = all
        .where(matchesFilter)
        .where((e) => category == null || e.category == category)
        .where((e) => day == null || _sameDay(e.startDate, day))
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    return list;
  }
}
