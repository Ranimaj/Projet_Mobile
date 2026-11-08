import 'package:campusconnect/models/event_model.dart';
import 'package:campusconnect/screens/evenements/ticket_rules.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  final start = DateTime(2026, 11, 10, 18, 0); // fin par défaut : 20 h

  EventModel ev({
    String id = 'evt-123',
    double? price = 10,
    List<String> registered = const ['stud1'],
    List<String> present = const [],
    List<String> paid = const [],
    EventStatus status = EventStatus.active,
  }) =>
      EventModel(
        id: id,
        organizerId: 'org',
        organizerName: 'Club',
        title: 'Atelier photo',
        description: 'Description',
        category: 'Culture',
        startDate: start,
        location: 'Hall principal',
        price: price,
        registeredUserIds: registered,
        checkedInUserIds: present,
        paidUserIds: paid,
        status: status,
      );

  group('contenu du QR : CC1|<eventId>|<uid>', () {
    test('construction', () => expect(TicketRules.buildTicketPayload('evt-123', 'stud1'), 'CC1|evt-123|stud1'));
    test('aller-retour', () {
      final t = TicketRules.parseTicketPayload(TicketRules.buildTicketPayload('evt-123', 'Ab_9'));
      expect(t?.eventId, 'evt-123');
      expect(t?.uid, 'Ab_9');
    });
    test('espaces / retour à la ligne AUTOUR : tolérés', () {
      expect(TicketRules.parseTicketPayload('  CC1|evt-123|stud1\n')?.uid, 'stud1');
    });
    test('espaces À L’INTÉRIEUR : refusé (lecture stricte)', () {
      expect(TicketRules.parseTicketPayload('CC1 | evt-123 | stud1'), isNull);
      expect(TicketRules.parseTicketPayload('CC1|evt 123|stud1'), isNull);
    });
    test('mauvais préfixe : refusé', () {
      expect(TicketRules.parseTicketPayload('CC2|evt-123|stud1'), isNull);
      expect(TicketRules.parseTicketPayload('cc1|evt-123|stud1'), isNull);
    });
    test('parties manquantes ou en trop : refusé', () {
      expect(TicketRules.parseTicketPayload('CC1|evt-123'), isNull);
      expect(TicketRules.parseTicketPayload('CC1||stud1'), isNull);
      expect(TicketRules.parseTicketPayload('CC1|evt-123|'), isNull);
      expect(TicketRules.parseTicketPayload('CC1|evt-123|stud1|extra'), isNull);
    });
    test('texte quelconque, vide ou null : refusé', () {
      expect(TicketRules.parseTicketPayload('https://exemple.com'), isNull);
      expect(TicketRules.parseTicketPayload(''), isNull);
      expect(TicketRules.parseTicketPayload(null), isNull);
    });
    test('caractères interdits : refusé', () {
      expect(TicketRules.parseTicketPayload('CC1|evt/123|stud1'), isNull);
      expect(TicketRules.parseTicketPayload('CC1|evt-123|<script>'), isNull);
    });
  });

  group('accès au billet', () {
    final before = start.subtract(const Duration(days: 1));
    test('inscrit, à venir : autorisé', () => expect(TicketRules.ticketBlockedReason(ev(), 'stud1', before), isNull));
    test('pas inscrit / non connecté : refusé', () {
      expect(TicketRules.ticketBlockedReason(ev(), 'autre', before), isNotNull);
      expect(TicketRules.ticketBlockedReason(ev(), null, before), isNotNull);
    });
    test('terminé : refusé', () {
      expect(TicketRules.ticketBlockedReason(ev(), 'stud1', start.add(const Duration(hours: 2))),
          'Événement terminé : billet indisponible.');
    });
    test('annulé : visible (billet « Annulé »)', () {
      expect(TicketRules.ticketBlockedReason(ev(status: EventStatus.cancelled), 'stud1', before), isNull);
    });
  });

  group('puces du billet', () {
    test('Gratuit / À payer sur place / Payé ✓', () {
      expect(TicketRules.paymentLabel(TicketRules.payment(ev(price: null), 'stud1')), 'Gratuit');
      expect(TicketRules.paymentLabel(TicketRules.payment(ev(), 'stud1')), 'À payer sur place');
      expect(TicketRules.paymentLabel(TicketRules.payment(ev(paid: ['stud1']), 'stud1')), 'Payé ✓');
    });
    test('présent', () {
      expect(TicketRules.isPresent(ev(present: ['stud1']), 'stud1'), isTrue);
      expect(TicketRules.isPresent(ev(), 'stud1'), isFalse);
    });
  });

  group('partage', () {
    test('message : titre, date, lieu, prix, invitation', () {
      expect(
          TicketRules.shareMessage(ev()),
          'Atelier photo\n'
          'Date : Mardi 10 novembre 2026 à 18:00\n'
          'Lieu : Hall principal\n'
          'Prix : 10 TND\n'
          '\n'
          'Rejoins-moi sur CampusConnect !');
    });
    test('gratuit : « Gratuit »', () => expect(TicketRules.shareMessage(ev(price: null)), contains('Prix : Gratuit')));
    test('annulé : partage désactivé', () {
      expect(TicketRules.shareBlockedReason(ev(status: EventStatus.cancelled)), 'Événement annulé : partage désactivé.');
      expect(TicketRules.shareBlockedReason(ev()), isNull);
    });
  });

  group('verdict du scan', () {
    final during = start.add(const Duration(minutes: 10));
    test('billet valide, inscrit, pas encore pointé : à pointer', () {
      final r = TicketRules.scanVerdict(ev(), 'CC1|evt-123|stud1', during);
      expect(r.verdict, ScanVerdict.markPresent);
      expect(r.uid, 'stud1');
    });
    test('déjà pointé', () {
      expect(TicketRules.scanVerdict(ev(present: ['stud1']), 'CC1|evt-123|stud1', during).verdict,
          ScanVerdict.alreadyPresent);
    });
    test('texte qui n’est pas un billet : invalide', () {
      expect(TicketRules.scanVerdict(ev(), 'bonjour', during).verdict, ScanVerdict.invalid);
    });
    test('billet d’un autre événement', () {
      expect(TicketRules.scanVerdict(ev(), 'CC1|evt-999|stud1', during).verdict, ScanVerdict.otherEvent);
    });
    test('faux billet pour quelqu’un de non inscrit : refusé', () {
      expect(TicketRules.scanVerdict(ev(), 'CC1|evt-123|intrus', during).verdict, ScanVerdict.notRegistered);
    });
    test('trop tôt : bloqué avec la raison', () {
      final r = TicketRules.scanVerdict(ev(), 'CC1|evt-123|stud1', start.subtract(const Duration(hours: 3)));
      expect(r.verdict, ScanVerdict.blocked);
      expect(r.reason, contains('1 h avant'));
    });
    test('annulé : bloqué', () {
      expect(TicketRules.scanVerdict(ev(status: EventStatus.cancelled), 'CC1|evt-123|stud1', during).verdict,
          ScanVerdict.blocked);
    });
  });
}
