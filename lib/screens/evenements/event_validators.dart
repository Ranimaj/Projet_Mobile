import '../../core/constants/app_constants.dart';
import '../../models/event_model.dart';

/// Contrôles de saisie du module Événements.
///
/// Fonctions pures : elles reçoivent tout ce dont elles ont besoin (y compris
/// l'heure « maintenant ») et renvoient null si la valeur est valide, sinon le
/// message d'erreur à afficher. Aucune dépendance à Flutter ou Firebase :
/// elles sont donc testables unitairement.
class EventValidators {
  EventValidators._();

  static const int titleMin = 3, titleMax = 80;
  static const int descriptionMin = 10, descriptionMax = 1000;
  static const int locationMin = 3, locationMax = 100;
  static const int capacityMin = 1, capacityMax = 5000;
  static const Duration minLeadTime = Duration(minutes: 15);
  static const Duration maxLeadTime = Duration(days: 365);
  static const Duration minDuration = Duration(minutes: 15);
  static const Duration maxDuration = Duration(hours: 72);
  static const int posterMaxBytes = 5 * 1024 * 1024; // 5 Mo avant compression
  static const int maxEventsPerDay = 5;

  static const String lieuIntrouvable = 'Lieu introuvable sur la carte';

  /// Supprime les espaces au début et à la fin, et remplace les espaces
  /// répétés à l'intérieur par un seul. Les retours à la ligne sont gardés
  /// (utile pour la description).
  static String normalize(String? value) =>
      (value ?? '').trim().replaceAll(RegExp(r'[ \t]+'), ' ');

  static String? title(String? value) {
    final v = normalize(value);
    if (v.length < titleMin || v.length > titleMax) return 'Titre requis (3 à 80 caractères)';
    if (!RegExp(r'\p{L}', unicode: true).hasMatch(v)) {
      return 'Le titre doit contenir au moins une lettre';
    }
    return null;
  }

  static String? description(String? value) {
    final v = normalize(value);
    if (v.length < descriptionMin || v.length > descriptionMax) {
      return 'Description requise (10 à 1000 caractères)';
    }
    return null;
  }

  static String? location(String? value) {
    final v = normalize(value);
    if (v.length < locationMin || v.length > locationMax) return 'Lieu requis (3 à 100 caractères)';
    return null;
  }

  static String? category(String? value) {
    if (value == null || !AppConstants.eventCategories.contains(value)) return 'Catégorie invalide';
    return null;
  }

  /// Début : au moins 15 min dans le futur (couvre aussi « aujourd'hui avec
  /// une heure passée ») et au plus 365 jours à l'avance.
  static String? start(DateTime? start, {required DateTime now}) {
    if (start == null || start.isBefore(now.add(minLeadTime))) {
      return "L'événement doit commencer dans le futur";
    }
    if (start.isAfter(now.add(maxLeadTime))) return "Au plus 365 jours à l'avance";
    return null;
  }

  /// Fin : strictement après le début, durée entre 15 min et 72 h.
  static String? end(DateTime? start, DateTime? end) {
    const message = 'La fin doit être après le début (15 min à 72 h)';
    if (start == null || end == null) return message;
    final duration = end.difference(start);
    if (duration < minDuration || duration > maxDuration) return message;
    return null;
  }

  /// Capacité optionnelle (champ vide = illimitée). En modification,
  /// [registeredCount] empêche de descendre sous le nombre d'inscrits.
  static String? capacity(String? value, {int registeredCount = 0}) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    final message = registeredCount > 0
        ? 'Entre 1 et 5000 (minimum : $registeredCount inscrits)'
        : 'Entre 1 et 5000';
    if (!RegExp(r'^\d+$').hasMatch(v)) return message;
    final n = int.parse(v);
    if (n < capacityMin || n > capacityMax || n < registeredCount) return message;
    return null;
  }

  /// Affiche optionnelle : JPG ou PNG, 5 Mo maximum avant compression.
  static String? poster({String? fileName, int? sizeBytes}) {
    if (fileName == null) return null; // pas d'affiche : autorisé
    final ext = fileName.split('.').last.toLowerCase();
    if (!['jpg', 'jpeg', 'png'].contains(ext)) return 'Format non supporté : JPG ou PNG uniquement';
    if (sizeBytes != null && sizeBytes > posterMaxBytes) return 'Image trop lourde (5 Mo maximum)';
    return null;
  }

  /// Coordonnées optionnelles, mais si présentes elles doivent être réelles.
  static String? coordinates(double? latitude, double? longitude) {
    if (latitude == null && longitude == null) return null;
    if (latitude == null || longitude == null) return 'Coordonnées incomplètes';
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      return 'Coordonnées invalides';
    }
    return null;
  }

  /// Raison pour laquelle [event] ne peut plus être modifié à [now], ou null.
  static String? editBlocked(EventModel event, DateTime now) {
    switch (event.statusAt(now)) {
      case EventDisplayStatus.cancelled:
        return 'Un événement annulé ne peut plus être modifié.';
      case EventDisplayStatus.finished:
        return 'Un événement terminé ne peut plus être modifié.';
      default:
        return null;
    }
  }

  /// Titre comparable : normalisé et en minuscules.
  static String normalizedTitle(String title) => normalize(title).toLowerCase();

  /// Doublon : même organisateur, même titre normalisé, même début (à la minute).
  /// [ignoreId] exclut l'événement en cours de modification.
  static String? duplicate({
    required String organizerId,
    required String title,
    required DateTime start,
    required List<EventModel> existing,
    String? ignoreId,
  }) {
    final t = normalizedTitle(title);
    final startMinute = DateTime(start.year, start.month, start.day, start.hour, start.minute);
    final found = existing.any((e) =>
        e.id != ignoreId &&
        e.organizerId == organizerId &&
        normalizedTitle(e.title) == t &&
        DateTime(e.startDate.year, e.startDate.month, e.startDate.day, e.startDate.hour,
                e.startDate.minute) ==
            startMinute);
    return found ? 'Vous avez déjà créé cet événement à cette date' : null;
  }

  /// Anti-spam « doux » : 5 créations max par organisateur et par jour.
  /// Vérification côté app uniquement (contournable) : un vrai plafond
  /// demanderait un compteur côté serveur.
  static String? dailyLimit({
    required String organizerId,
    required List<EventModel> existing,
    required DateTime now,
  }) {
    final today = existing.where((e) =>
        e.organizerId == organizerId &&
        e.createdAt.year == now.year &&
        e.createdAt.month == now.month &&
        e.createdAt.day == now.day);
    return today.length >= maxEventsPerDay
        ? 'Limite atteinte : 5 événements par jour maximum'
        : null;
  }
}
