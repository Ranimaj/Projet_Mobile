import 'package:campusconnect/models/event_model.dart';
import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/screens/evenements/event_rules.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Étape 12 : outils organisateur (participants, présence, paiement).
void main() {
  final start = DateTime(2026, 11, 10, 18, 0); // fin par défaut : 20 h

  EventModel ev({
    String organizerId = 'org',
    double? price = 10,
    int? capacity = 4,
    List<String> registered = const ['a', 'b', 'c'],
    List<String> present = const [],
    List<String> paid = const [],
    EventStatus status = EventStatus.active,
  }) =>
      EventModel(
        id: 'e',
        organizerId: organizerId,
        organizerName: 'Club',
        title: 'Atelier',
        description: 'Description',
        category: 'Culture',
        startDate: start,
        location: 'Hall',
        price: price,
        capacity: capacity,
        registeredUserIds: registered,
        checkedInUserIds: present,
        paidUserIds: paid,
        status: status,
      );

  AppUser user(String id, {UserRole role = UserRole.student}) =>
      AppUser(id: id, fullName: 'Nom $id', email: '$id@esprit.tn', role: role, createdAt: DateTime(2026, 1, 1));

  group('modèle : paidUserIds', () {
    test('ancien document : listes vides par défaut', () {
      final e = EventModel.fromMap('old', {
        'title': 'Ancien',
        'description': 'Document ancien',
        'category': 'Sport',
        'location': 'Stade',
        'startDate': Timestamp.fromDate(start),
      });
      expect(e.paidUserIds, isEmpty);
      expect(e.checkedInUserIds, isEmpty);
    });
    test('toMap / fromMap / copyWith gardent paidUserIds', () {
      final e = ev(paid: ['a']);
      expect(EventModel.fromMap('e', e.toMap()).paidUserIds, ['a']);
      expect(e.copyWith(title: 'Autre').paidUserIds, ['a']);
      expect(e.copyWith(paidUserIds: ['b']).paidUserIds, ['b']);
    });
    test('jamais dans les champs du formulaire de modification', () {
      expect(EventModel.editableFields, isNot(contains('paidUserIds')));
      expect(EventModel.editableFields, isNot(contains('checkedInUserIds')));
      final e = ev(paid: ['a'], present: ['a']);
      expect(e.copyWith(paidUserIds: [], checkedInUserIds: []).changedFieldsSince(e), isEmpty);
    });
    test('désinscription : retiré aussi des présents et des payés', () {
      final e = ev(present: ['a', 'b'], paid: ['a', 'c']).copyWithRegistration('a', false);
      expect(e.registeredUserIds, ['b', 'c']);
      expect(e.checkedInUserIds, ['b']);
      expect(e.paidUserIds, ['c']);
    });
    test('inscription : présents et payés inchangés', () {
      final e = ev(present: ['b'], paid: ['c']).copyWithRegistration('z', true);
      expect(e.checkedInUserIds, ['b']);
      expect(e.paidUserIds, ['c']);
    });
  });

  group('canManageAttendees', () {
    test('organisateur : oui', () => expect(EventRules.canManageAttendees(ev(), user('org')), isTrue));
    test('admin : oui', () => expect(EventRules.canManageAttendees(ev(), user('x', role: UserRole.admin)), isTrue));
    test('autre étudiant : non', () => expect(EventRules.canManageAttendees(ev(), user('a')), isFalse));
    test('recruteur : non', () => expect(EventRules.canManageAttendees(ev(), user('r', role: UserRole.recruiter)), isFalse));
    test('non connecté : non', () => expect(EventRules.canManageAttendees(ev(), null), isFalse));
  });

  group('canMarkPresent (à partir d’1 h avant, jusqu’à la fin)', () {
    test('1 h 01 avant le début : refusé', () {
      expect(EventRules.canMarkPresent(ev(), 'a', start.subtract(const Duration(hours: 1, minutes: 1))), isFalse);
    });
    test('exactement 1 h avant : autorisé', () {
      expect(EventRules.canMarkPresent(ev(), 'a', start.subtract(const Duration(hours: 1))), isTrue);
    });
    test('pendant l’événement : autorisé', () {
      expect(EventRules.canMarkPresent(ev(), 'a', start.add(const Duration(minutes: 30))), isTrue);
    });
    test('terminé (exactement à la fin) : refusé, lecture seule', () {
      expect(EventRules.presentBlockedReason(ev(), 'a', start.add(const Duration(hours: 2))),
          'Événement terminé : présences en lecture seule.');
    });
    test('pas inscrit : refusé', () => expect(EventRules.canMarkPresent(ev(), 'z', start), isFalse));
    test('annulé : refusé', () {
      expect(EventRules.presentBlockedReason(ev(status: EventStatus.cancelled), 'a', start),
          'Événement annulé : liste en lecture seule.');
    });
  });

  group('canMarkPaid', () {
    test('payant, inscrit, actif : autorisé', () => expect(EventRules.canMarkPaid(ev(), 'a'), isTrue));
    test('gratuit (null ou 0) : refusé', () {
      expect(EventRules.canMarkPaid(ev(price: null), 'a'), isFalse);
      expect(EventRules.paidBlockedReason(ev(price: 0), 'a'), 'Événement gratuit : rien à payer.');
    });
    test('pas inscrit : refusé', () => expect(EventRules.canMarkPaid(ev(), 'z'), isFalse));
    test('annulé : refusé', () => expect(EventRules.canMarkPaid(ev(status: EventStatus.cancelled), 'a'), isFalse));
    test('terminé : encore autorisé (paiement noté après coup)', () {
      expect(EventRules.canMarkPaid(ev(), 'a'), isTrue); // pas de condition de date
    });
  });

  group('attendeeStats', () {
    test('compte inscrits, présents, payés, recette et remplissage', () {
      final s = EventRules.attendeeStats(ev(present: ['a', 'b'], paid: ['a']));
      expect(s.registered, 3);
      expect(s.capacity, 4);
      expect(s.present, 2);
      expect(s.paid, 1);
      expect(s.expectedRevenue, 10);
      expect(s.fillRatio, 0.75);
    });
    test('recette = prix × payés, arrondie au centime', () {
      expect(EventRules.attendeeStats(ev(price: 12.5, paid: ['a', 'b', 'c'])).expectedRevenue, 37.5);
    });
    test('gratuit : recette 0 ; sans capacité : pas de remplissage', () {
      final s = EventRules.attendeeStats(ev(price: null, capacity: null));
      expect(s.expectedRevenue, 0);
      expect(s.fillRatio, isNull);
      expect(s.capacity, isNull);
    });
    test('entrées isolées (plus inscrit) ou en double : ignorées', () {
      final s = EventRules.attendeeStats(ev(present: ['a', 'a', 'ancien'], paid: ['ancien']));
      expect(s.present, 1);
      expect(s.paid, 0);
    });
  });

  test('nom de repli : « Étudiant » + 4 derniers caractères', () {
    expect(EventRules.fallbackName('K8sP2qXyZ9ab'), 'Étudiant Z9ab');
    expect(EventRules.fallbackName('abc'), 'Étudiant abc');
  });

  group('filterAttendees', () {
    final names = {'a': 'Émna Ben Ali', 'b': 'Yassine Trabelsi', 'c': 'amine Gharbi'};
    final e = ev(present: ['a'], paid: ['b']);
    List<String> uids(List<({String uid, String name})> l) => l.map((x) => x.uid).toList();

    test('Tous : trié par nom sans accents ni majuscules', () {
      expect(uids(EventRules.filterAttendees(e, names)), ['c', 'a', 'b']); // amine, Émna, Yassine
    });
    test('Présents / Absents', () {
      expect(uids(EventRules.filterAttendees(e, names, filter: AttendeeFilter.present)), ['a']);
      expect(uids(EventRules.filterAttendees(e, names, filter: AttendeeFilter.absent)), ['c', 'b']);
    });
    test('Non payés', () {
      expect(uids(EventRules.filterAttendees(e, names, filter: AttendeeFilter.unpaid)), ['c', 'a']);
    });
    test('recherche sans accents : « emna » trouve « Émna »', () {
      expect(uids(EventRules.filterAttendees(e, names, query: 'emna')), ['a']);
    });
    test('recherche + filtre combinés', () {
      expect(EventRules.filterAttendees(e, names, filter: AttendeeFilter.present, query: 'yassine'), isEmpty);
    });
    test('nom inconnu : nom de repli, et on peut le chercher', () {
      final list = EventRules.filterAttendees(ev(registered: ['zzzz1234']), const {});
      expect(list.single.name, 'Étudiant 1234');
      expect(EventRules.filterAttendees(ev(registered: ['zzzz1234']), const {}, query: 'etudiant').length, 1);
    });
    test('aucun inscrit : liste vide', () {
      expect(EventRules.filterAttendees(ev(registered: []), names), isEmpty);
    });
  });
}
