import 'package:intl/intl.dart';
import '../../models/event_model.dart';
import 'event_rules.dart';

/// État de paiement affiché sur le billet.
enum TicketPayment { free, toPay, paid }

/// Résultat d'un scan de billet par l'organisateur.
enum ScanVerdict { markPresent, alreadyPresent, invalid, otherEvent, notRegistered, blocked }

/// Règles PURES du billet (« Mon billet »), du partage et du scan.
///
/// SÉCURITÉ (honnêtement) : le QR n'est PAS signé, ce n'est qu'un
/// identifiant « CC1|<eventId>|<uid> ». N'importe qui peut fabriquer ce
/// texte. Ce qui protège le pointage : on vérifie toujours que l'uid est
/// dans registeredUserIds de l'événement, et les règles Firestore n'acceptent
/// le pointage que de l'organisateur (ou d'un admin) et pour une personne
/// inscrite. Un faux QR pour quelqu'un de non inscrit est donc refusé ; un
/// QR copié d'un inscrit pointerait cet inscrit (comme un billet papier).
class TicketRules {
  TicketRules._();

  static const String prefix = 'CC1';
  static final RegExp _id = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  /// Contenu du QR : « CC1|<eventId>|<uid> ».
  static String buildTicketPayload(String eventId, String uid) => '$prefix|$eventId|$uid';

  /// Lecture STRICTE : exactement 3 parties, préfixe « CC1 », identifiants
  /// simples (lettres, chiffres, « - », « _ »). Seuls les espaces autour du
  /// texte entier sont tolérés (retour à la ligne d'un lecteur) ; un espace
  /// à l'intérieur rend le billet invalide. Renvoie null si invalide.
  static ({String eventId, String uid})? parseTicketPayload(String? raw) {
    if (raw == null) return null;
    final parts = raw.trim().split('|');
    if (parts.length != 3 || parts[0] != prefix) return null;
    if (!_id.hasMatch(parts[1]) || !_id.hasMatch(parts[2])) return null;
    return (eventId: parts[1], uid: parts[2]);
  }

  /// Raison de NE PAS proposer « Mon billet », ou null. Inscrit et événement
  /// pas terminé ; un événement annulé reste visible (billet « Annulé »).
  static String? ticketBlockedReason(EventModel event, String? uid, DateTime now) {
    if (uid == null || !event.isUserRegistered(uid)) return "Vous n'êtes pas inscrit à cet événement.";
    if (!now.isBefore(event.endDate)) return 'Événement terminé : billet indisponible.';
    return null;
  }

  static TicketPayment payment(EventModel event, String uid) {
    if (EventRules.isFree(event)) return TicketPayment.free;
    return event.paidUserIds.contains(uid) ? TicketPayment.paid : TicketPayment.toPay;
  }

  static String paymentLabel(TicketPayment p) {
    switch (p) {
      case TicketPayment.free:
        return 'Gratuit';
      case TicketPayment.toPay:
        return 'À payer sur place';
      case TicketPayment.paid:
        return 'Payé ✓';
    }
  }

  static bool isPresent(EventModel event, String uid) => event.checkedInUserIds.contains(uid);

  /// Partage désactivé pour un événement annulé.
  static String? shareBlockedReason(EventModel event) =>
      event.status == EventStatus.cancelled ? 'Événement annulé : partage désactivé.' : null;

  /// Texte partagé (sans lien profond) : titre, date, lieu, prix, invitation.
  static String shareMessage(EventModel event) {
    final date = DateFormat("EEEE d MMMM yyyy 'à' HH:mm", 'fr_FR').format(event.startDate);
    return '${event.title}\n'
        'Date : ${date[0].toUpperCase()}${date.substring(1)}\n'
        'Lieu : ${event.location}\n'
        'Prix : ${EventRules.priceLabel(event)}\n'
        '\n'
        'Rejoins-moi sur CampusConnect !';
  }

  /// Verdict d'un scan pour [event] : billet lisible ? bon événement ?
  /// personne inscrite ? déjà pointée ? pointage permis maintenant ?
  /// (Le scan ne fait que POINTER présent, jamais l'inverse.)
  static ({ScanVerdict verdict, String? uid, String? reason}) scanVerdict(
      EventModel event, String? raw, DateTime now) {
    final ticket = parseTicketPayload(raw);
    if (ticket == null) return (verdict: ScanVerdict.invalid, uid: null, reason: null);
    if (ticket.eventId != event.id) return (verdict: ScanVerdict.otherEvent, uid: ticket.uid, reason: null);
    if (!event.isUserRegistered(ticket.uid)) {
      return (verdict: ScanVerdict.notRegistered, uid: ticket.uid, reason: null);
    }
    if (isPresent(event, ticket.uid)) return (verdict: ScanVerdict.alreadyPresent, uid: ticket.uid, reason: null);
    final blocked = EventRules.presentBlockedReason(event, ticket.uid, now);
    if (blocked != null) return (verdict: ScanVerdict.blocked, uid: ticket.uid, reason: blocked);
    return (verdict: ScanVerdict.markPresent, uid: ticket.uid, reason: null);
  }
}
