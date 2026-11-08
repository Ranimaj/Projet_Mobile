import '../../models/event_model.dart';

/// Ce qu'on envoie au calendrier du téléphone (données simples, sans plugin).
class CalendarEntry {
  final String title;
  final String description;
  final String location;
  final DateTime start;
  final DateTime end;

  /// Rappel souhaité, en minutes AVANT le début.
  final int alarmMinutes;

  const CalendarEntry({
    required this.title,
    required this.description,
    required this.location,
    required this.start,
    required this.end,
    required this.alarmMinutes,
  });
}

/// BF9 / Avancé 1 — logique PURE de la synchronisation calendrier : quoi
/// envoyer et quand refuser. Aucune dépendance au plugin : testable sans
/// téléphone. L'appel au plugin est dans event_calendar_launcher.dart.
class EventCalendarSync {
  EventCalendarSync._();

  /// Rappel demandé : 30 minutes avant le début.
  ///
  /// LIMITE (à connaître) :
  /// - iOS : le plugin crée vraiment cette alarme (30 min avant).
  /// - Android : le plugin ouvre l'application Calendrier avec un événement
  ///   pré-rempli (Intent ACTION_INSERT). Cet Intent n'a PAS de champ pour le
  ///   rappel : c'est le rappel par défaut de l'application Calendrier qui
  ///   s'applique (souvent 30 min dans Google Agenda, mais c'est un réglage
  ///   de l'utilisateur), et l'utilisateur peut le changer avant d'enregistrer.
  ///   Garantir l'alarme sur Android demanderait les permissions
  ///   READ/WRITE_CALENDAR et une écriture directe : non retenu ici.
  static const int reminderMinutes = 30;

  /// Raison de refuser l'ajout, ou null. Un événement annulé n'a pas sa
  /// place dans un agenda.
  static String? blockedReason(EventModel event) {
    if (event.status == EventStatus.cancelled) {
      return 'Événement annulé : il ne peut pas être ajouté au calendrier.';
    }
    return null;
  }

  /// Remarque à afficher après l'ajout (null = rien à signaler) : un
  /// événement terminé peut être ajouté, mais pour mémoire seulement.
  static String? note(EventModel event, DateTime now) {
    if (!now.isBefore(event.endDate)) return 'Événement déjà terminé : ajouté pour mémoire.';
    return null;
  }

  /// Texte de la description dans l'agenda : catégorie et organisateur en
  /// tête, puis la description de l'événement.
  static String descriptionText(EventModel event) {
    final organizer = event.organizerName.trim().isEmpty ? 'organisateur inconnu' : event.organizerName.trim();
    return '${event.category} · organisé par $organizer\n\n${event.description.trim()}\n\n'
        '— Ajouté depuis CampusConnect';
  }

  /// Entrée d'agenda avec les VRAIES dates de début et de fin (plus de
  /// « 2 heures » codées en dur). Pour un ancien document sans date de fin,
  /// le modèle fournit déjà sa valeur par défaut (début + 2 h).
  static CalendarEntry buildEntry(EventModel event) {
    return CalendarEntry(
      title: event.title.trim(),
      description: descriptionText(event),
      location: event.location.trim(),
      start: event.startDate,
      end: event.endDate,
      alarmMinutes: reminderMinutes,
    );
  }
}
