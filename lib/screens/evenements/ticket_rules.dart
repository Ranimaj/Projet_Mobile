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
/// identifiant « CC1|<eventId>|<uid> » (dans une adresse web pour les
/// nouveaux billets : le reste de l'adresse n'est que de l'affichage). N'importe qui peut fabriquer ce
/// texte. Ce qui protège le pointage : on vérifie toujours que l'uid est
/// dans registeredUserIds de l'événement, et seul l'organisateur (ou un
/// admin) a accès à l'écran de pointage. Un faux QR pour quelqu'un de non inscrit est donc refusé ; un
/// QR copié d'un inscrit pointerait cet inscrit (comme un billet papier).
class TicketRules {
  TicketRules._();

  static const String prefix = 'CC1';
  static final RegExp _id = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  /// Adresse de la page web du billet (docs/billet/index.html). Le QR du
  /// billet est « <adresse>#<CC1|eventId|uid encodé>?… » : l'appareil photo
  /// d'un téléphone ouvre la page. Autre adresse à la compilation :
  /// --dart-define=BILLET_BASE_URL=https://…/billet/
  static const String billetBaseUrl = String.fromEnvironment(
    'BILLET_BASE_URL',
    defaultValue: 'https://abdelaziz-belkhiria.github.io/campus-billet/',
  );

  /// Anciennes adresses de la page : les billets créés avant le changement
  /// d'hébergement (écran ouvert, capture) restent lisibles au scan.
  static const List<String> legacyBilletBaseUrls = ['https://ranimaj.github.io/Projet_Mobile/billet/'];

  /// Identifiant vérifié du billet : « CC1|<eventId>|<uid> ». C'est la seule
  /// partie du QR utilisée au pointage (voir ticket_link.dart pour l'adresse
  /// complète affichée dans le QR).
  static String buildTicketPayload(String eventId, String uid) => '$prefix|$eventId|$uid';

  /// « CC1|… » contenu dans une adresse de billet, ou null : l'adresse doit
  /// commencer par [baseUrl] suivi de « # » ; le fragment (jusqu'au « ? »)
  /// est décodé. Tout ce qui suit le « ? » est de l'affichage, ignoré ici.
  static String? payloadFromLink(String raw, {String baseUrl = billetBaseUrl}) {
    if (baseUrl.isEmpty || !raw.startsWith('$baseUrl#')) return null;
    final fragment = raw.substring(baseUrl.length + 1);
    final q = fragment.indexOf('?');
    try {
      final decoded = Uri.decodeComponent(q == -1 ? fragment : fragment.substring(0, q));
      return decoded == decoded.trim() ? decoded : null;
    } catch (_) {
      return null; // encodage « % » invalide
    }
  }

  /// Lecture STRICTE : exactement 3 parties, préfixe « CC1 », identifiants
  /// simples (lettres, chiffres, « - », « _ »). Seuls les espaces autour du
  /// texte entier sont tolérés (retour à la ligne d'un lecteur) ; un espace
  /// à l'intérieur rend le billet invalide. Renvoie null si invalide.
  ///
  /// Deux formes acceptées : le texte « CC1|… » des anciens billets, et
  /// l'adresse web des nouveaux, seulement si elle commence par [baseUrl]
  /// (ou une des [legacyBilletBaseUrls]) et que son fragment est un
  /// « CC1|… » valide.
  static ({String eventId, String uid})? parseTicketPayload(String? raw, {String baseUrl = billetBaseUrl}) {
    if (raw == null) return null;
    final text = raw.trim();
    String? fromLink;
    for (final base in [baseUrl, ...legacyBilletBaseUrls]) {
      fromLink = payloadFromLink(text, baseUrl: base);
      if (fromLink != null) break;
    }
    final parts = (fromLink ?? text).split('|');
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
