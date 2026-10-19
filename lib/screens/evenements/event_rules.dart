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

  /// Date sans l'heure (minuit), pour comparer des jours.
  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Nombre de jours du mois (le « jour 0 » du mois suivant = dernier jour).
  static int daysInMonth(DateTime month) => DateTime(month.year, month.month + 1, 0).day;

  /// Cases de la grille du mois, semaine commençant le lundi : null avant le
  /// 1er (décalage) et après le dernier jour (pour finir la semaine).
  static List<DateTime?> monthGrid(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final offset = first.weekday - DateTime.monday; // lundi = 0 ... dimanche = 6
    final cells = <DateTime?>[
      for (var i = 0; i < offset; i++) null,
      for (var d = 1; d <= daysInMonth(month); d++) DateTime(month.year, month.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return cells;
  }

  /// Compte à rebours lisible jusqu'au début : « dans 25 min », « dans 3 h »
  /// (moins de 6 h), « aujourd'hui », « demain », « dans 4 jours ».
  /// Les jours sont comptés en jours de calendrier (arrondi : sûr même lors
  /// d'un changement d'heure).
  static String countdown(DateTime start, DateTime now) {
    final diff = start.difference(now);
    if (diff.isNegative) return 'en cours';
    if (diff.inMinutes < 60) return 'dans ${diff.inMinutes < 1 ? 1 : diff.inMinutes} min';
    if (diff.inHours < 6) return 'dans ${diff.inHours} h';
    final days = (dateOnly(start).difference(dateOnly(now)).inHours / 24).round();
    if (days == 0) return "aujourd'hui";
    if (days == 1) return 'demain';
    return 'dans $days jours';
  }

  /// Nombre de filtres actifs affiché sur l'icône filtre : catégorie et jour.
  static int activeFilterCount({String? category, DateTime? day}) =>
      (category == null ? 0 : 1) + (day == null ? 0 : 1);

  /// Pour chaque jour : les catégories distinctes des événements qui y
  /// commencent, dans l'ordre d'apparition (un point de couleur par catégorie).
  static Map<DateTime, List<String>> categoriesByDay(List<EventModel> events) {
    final byDay = <DateTime, List<String>>{};
    for (final e in events) {
      final categories = byDay.putIfAbsent(dateOnly(e.startDate), () => []);
      if (!categories.contains(e.category)) categories.add(e.category);
    }
    return byDay;
  }

  /// Jours (sans l'heure) où commence au moins un des [events] : on y met un point.
  static Set<DateTime> eventDays(List<EventModel> events) => {for (final e in events) dateOnly(e.startDate)};

  static const Map<String, String> _accents = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a',
    'ç': 'c',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'î': 'i', 'ï': 'i', 'í': 'i', 'ì': 'i',
    'ô': 'o', 'ö': 'o', 'ó': 'o', 'ò': 'o', 'õ': 'o',
    'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
    'ÿ': 'y', 'ý': 'y', 'ñ': 'n', 'œ': 'oe', 'æ': 'ae',
  };

  /// Texte comparable pour la recherche : minuscules, sans accents, espaces
  /// réduits. « École » et « ecole » deviennent identiques.
  static String foldForSearch(String text) {
    final buffer = StringBuffer();
    for (final char in text.toLowerCase().split('')) {
      buffer.write(_accents[char] ?? char);
    }
    return buffer.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Recherche dans le titre et le lieu (requête vide = tout correspond).
  static bool matchesSearch(EventModel event, String query) {
    final q = foldForSearch(query);
    if (q.isEmpty) return true;
    return foldForSearch(event.title).contains(q) || foldForSearch(event.location).contains(q);
  }

  /// Règles 6, 8 et 12 : filtre principal + catégorie + jour + recherche,
  /// triés par date de début. Tous les filtres se combinent.
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
    String query = '',
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
        .where((e) => matchesSearch(e, query))
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    return list;
  }
}
