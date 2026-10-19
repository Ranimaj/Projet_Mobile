import 'package:campusconnect/models/event_model.dart';
import 'package:campusconnect/screens/evenements/event_rules.dart';
import 'package:campusconnect/screens/evenements/event_validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // « Maintenant » fixe : les tests ne dépendent pas de l'horloge réelle.
  final now = DateTime(2026, 10, 19, 10, 0);

  EventModel ev(
    String id, {
    DateTime? start,
    Duration duration = const Duration(hours: 2),
    String organizerId = 'org',
    String category = 'Sport',
    int? capacity,
    List<String> registered = const [],
    EventStatus status = EventStatus.active,
  }) {
    final s = start ?? DateTime(2026, 11, 1, 14, 0);
    return EventModel(
      id: id,
      organizerId: organizerId,
      organizerName: 'Club',
      title: 'Événement $id',
      description: 'Description',
      category: category,
      startDate: s,
      endDate: s.add(duration),
      location: 'Hall',
      capacity: capacity,
      registeredUserIds: registered,
      status: status,
    );
  }

  group('registrationBlocked (ordre : connecté, actif, pas terminé, pas commencé, pas inscrit, places)', () {
    test('tout est bon : autorisé', () {
      expect(EventRules.registrationBlocked(ev('e', capacity: 2, registered: ['a']), 'me', now), isNull);
    });
    test('non connecté', () {
      expect(EventRules.registrationBlocked(ev('e'), null, now), 'Connectez-vous pour vous inscrire.');
    });
    test('annulé', () {
      expect(EventRules.registrationBlocked(ev('e', status: EventStatus.cancelled), 'me', now),
          'Cet événement est annulé.');
    });
    test('terminé', () {
      final past = ev('e', start: DateTime(2026, 10, 1, 9, 0));
      expect(EventRules.registrationBlocked(past, 'me', now), 'Cet événement est terminé.');
    });
    test('en cours : inscriptions closes (comme request.time < startDate côté règles)', () {
      final ongoing = ev('e', start: now.subtract(const Duration(minutes: 30)));
      expect(EventRules.registrationBlocked(ongoing, 'me', now),
          "Les inscriptions sont closes : l'événement a commencé.");
    });
    test('déjà inscrit', () {
      expect(EventRules.registrationBlocked(ev('e', registered: ['me']), 'me', now), 'Vous êtes déjà inscrit.');
    });
    test('complet', () {
      expect(EventRules.registrationBlocked(ev('e', capacity: 1, registered: ['a']), 'me', now),
          'Complet : plus aucune place disponible.');
    });
    test("l'ordre compte : annulé ET complet → message « annulé »", () {
      final e = ev('e', status: EventStatus.cancelled, capacity: 1, registered: ['a']);
      expect(EventRules.registrationBlocked(e, 'me', now), 'Cet événement est annulé.');
    });
    test("l'ordre compte : non connecté avant tout le reste", () {
      final e = ev('e', status: EventStatus.cancelled);
      expect(EventRules.registrationBlocked(e, null, now), 'Connectez-vous pour vous inscrire.');
    });
  });

  group('unregistrationBlocked (jusqu’au début)', () {
    test('inscrit, avant le début : autorisé', () {
      expect(EventRules.unregistrationBlocked(ev('e', registered: ['me']), 'me', now), isNull);
    });
    test('pas inscrit : refusé', () {
      expect(EventRules.unregistrationBlocked(ev('e'), 'me', now), "Vous n'êtes pas inscrit.");
    });
    test('après le début : refusé', () {
      final started = ev('e', start: now, registered: ['me']);
      expect(EventRules.unregistrationBlocked(started, 'me', now),
          "Désinscription impossible : l'événement a commencé.");
    });
    test('annulé : refusé', () {
      final e = ev('e', status: EventStatus.cancelled, registered: ['me']);
      expect(EventRules.unregistrationBlocked(e, 'me', now), 'Cet événement est annulé.');
    });
  });

  group('conflit d’horaire', () {
    final target = ev('t', start: DateTime(2026, 11, 1, 14, 0)); // 14 h → 16 h

    test('chevauchement partiel : conflit', () {
      final other = ev('o', start: DateTime(2026, 11, 1, 15, 0), registered: ['me']);
      expect(EventRules.findConflict(target, [target, other], 'me', now)?.id, 'o');
    });
    test('l’un contient l’autre : conflit', () {
      final other = ev('o', start: DateTime(2026, 11, 1, 13, 0), duration: const Duration(hours: 5),
          registered: ['me']);
      expect(EventRules.findConflict(target, [other], 'me', now)?.id, 'o');
    });
    test('bout à bout (16 h / 16 h) : pas de conflit', () {
      final other = ev('o', start: DateTime(2026, 11, 1, 16, 0), registered: ['me']);
      expect(EventRules.findConflict(target, [other], 'me', now), isNull);
    });
    test('pas inscrit à l’autre : pas de conflit', () {
      final other = ev('o', start: DateTime(2026, 11, 1, 15, 0), registered: ['quelquun']);
      expect(EventRules.findConflict(target, [other], 'me', now), isNull);
    });
    test('autre événement annulé : ignoré', () {
      final other = ev('o', start: DateTime(2026, 11, 1, 15, 0), registered: ['me'], status: EventStatus.cancelled);
      expect(EventRules.findConflict(target, [other], 'me', now), isNull);
    });
    test('l’événement lui-même n’est pas un conflit', () {
      final self = ev('t', start: DateTime(2026, 11, 1, 14, 0), registered: ['me']);
      expect(EventRules.findConflict(target, [self], 'me', now), isNull);
    });
  });

  group('suppression et annulation', () {
    test('organisateur, sans inscrits : suppression autorisée', () {
      expect(EventRules.deleteBlocked(ev('e'), isAdmin: false), isNull);
    });
    test('organisateur, avec inscrits : refusée, annulation proposée', () {
      expect(EventRules.deleteBlocked(ev('e', registered: ['a', 'b']), isAdmin: false),
          "Impossible de supprimer : 2 inscrit(s). Annulez plutôt l'événement.");
    });
    test('admin, avec inscrits : autorisée (modération)', () {
      expect(EventRules.deleteBlocked(ev('e', registered: ['a']), isAdmin: true), isNull);
    });
    test('annulation : refusée si déjà annulé ou terminé', () {
      expect(EventRules.cancelBlocked(ev('e'), now), isNull);
      expect(EventRules.cancelBlocked(ev('e', status: EventStatus.cancelled), now), isNotNull);
      expect(EventRules.cancelBlocked(ev('e', start: DateTime(2026, 10, 1)), now), isNotNull);
    });
    test('motif : 5 à 200 caractères', () {
      expect(EventValidators.cancelReason('Pluie'), isNull);
      expect(EventValidators.cancelReason('Non'), isNotNull);
      expect(EventValidators.cancelReason('   '), isNotNull);
      expect(EventValidators.cancelReason('a' * 200), isNull);
      expect(EventValidators.cancelReason('a' * 201), isNotNull);
    });
  });

  group('recherche (sans accents, titre et lieu)', () {
    test('foldForSearch : minuscules, sans accents, espaces réduits', () {
      expect(EventRules.foldForSearch('  École   Supérieure '), 'ecole superieure');
      expect(EventRules.foldForSearch('ÇA Œuvre'), 'ca oeuvre');
    });
    final e = EventModel(
      id: 'x',
      organizerId: 'org',
      organizerName: 'Club',
      title: 'Journée portes ouvertes',
      description: 'Description',
      category: 'Associatif',
      startDate: DateTime(2026, 11, 1, 9, 0),
      location: 'École Polytechnique',
    );
    test('« ecole » trouve « École » (lieu)', () => expect(EventRules.matchesSearch(e, 'ecole'), isTrue));
    test('« JOURNEE » trouve « Journée » (titre)', () => expect(EventRules.matchesSearch(e, 'JOURNEE'), isTrue));
    test('requête vide : tout correspond', () => expect(EventRules.matchesSearch(e, '   '), isTrue));
    test('mot absent : pas de correspondance', () => expect(EventRules.matchesSearch(e, 'piscine'), isFalse));
    test('la description n’est pas cherchée', () => expect(EventRules.matchesSearch(e, 'description'), isFalse));
  });

  group('compte à rebours', () {
    final t = DateTime(2026, 10, 19, 10, 0);
    test('moins d’une heure : minutes', () {
      expect(EventRules.countdown(t.add(const Duration(minutes: 25)), t), 'dans 25 min');
      expect(EventRules.countdown(t.add(const Duration(seconds: 20)), t), 'dans 1 min');
    });
    test('moins de 6 h : heures', () {
      expect(EventRules.countdown(t.add(const Duration(hours: 3, minutes: 40)), t), 'dans 3 h');
    });
    test('plus tard le même jour : aujourd’hui', () {
      expect(EventRules.countdown(DateTime(2026, 10, 19, 20, 0), t), "aujourd'hui");
    });
    test('le lendemain : demain (même à moins de 24 h)', () {
      expect(EventRules.countdown(DateTime(2026, 10, 20, 9, 0), t), 'demain');
    });
    test('plus loin : en jours de calendrier', () {
      expect(EventRules.countdown(DateTime(2026, 10, 21, 8, 0), t), 'dans 2 jours');
      expect(EventRules.countdown(DateTime(2026, 11, 2, 8, 0), t), 'dans 14 jours'); // passe l'heure d'hiver
    });
    test('déjà commencé : en cours', () {
      expect(EventRules.countdown(t.subtract(const Duration(minutes: 5)), t), 'en cours');
    });
  });

  group('nombre de filtres actifs', () {
    test('0, 1 ou 2', () {
      expect(EventRules.activeFilterCount(), 0);
      expect(EventRules.activeFilterCount(category: 'Sport'), 1);
      expect(EventRules.activeFilterCount(category: 'Sport', day: DateTime(2026, 11, 1)), 2);
    });
  });

  group('grille du mois (lundi en premier)', () {
    test('octobre 2026 commence un jeudi : 3 cases vides, 31 jours, 35 cases', () {
      final cells = EventRules.monthGrid(DateTime(2026, 10));
      expect(cells.take(3), everyElement(isNull));
      expect(cells[3], DateTime(2026, 10, 1));
      expect(cells.whereType<DateTime>().length, 31);
      expect(cells.length, 35);
    });
    test('février 2027 commence un lundi : aucune case vide, 28 cases', () {
      final cells = EventRules.monthGrid(DateTime(2027, 2));
      expect(cells.first, DateTime(2027, 2, 1));
      expect(cells.length, 28);
    });
    test('novembre 2026 commence un dimanche : 6 cases vides, 42 cases', () {
      final cells = EventRules.monthGrid(DateTime(2026, 11));
      expect(cells.take(6), everyElement(isNull));
      expect(cells[6], DateTime(2026, 11, 1));
      expect(cells.length, 42);
    });
    test('nombre de jours, années bissextiles comprises', () {
      expect(EventRules.daysInMonth(DateTime(2026, 2)), 28);
      expect(EventRules.daysInMonth(DateTime(2028, 2)), 29);
      expect(EventRules.daysInMonth(DateTime(2026, 12)), 31);
    });
    test('jours avec événements : sans l’heure, sans doublon', () {
      final days = EventRules.eventDays([
        ev('a', start: DateTime(2026, 11, 1, 9, 0)),
        ev('b', start: DateTime(2026, 11, 1, 18, 30)),
        ev('c', start: DateTime(2026, 11, 3, 14, 0)),
      ]);
      expect(days, {DateTime(2026, 11, 1), DateTime(2026, 11, 3)});
    });
  });

  group('filtres combinés', () {
    final day1 = DateTime(2026, 11, 1, 18, 0);
    final day2 = DateTime(2026, 11, 2, 9, 0);
    final all = [
      ev('futurSport2', start: day2, category: 'Sport'),
      ev('futurSport1', start: day1, category: 'Sport', registered: ['me']),
      ev('futurCulture', start: day1.add(const Duration(hours: 1)), category: 'Culture', organizerId: 'me'),
      ev('annule', start: day1.add(const Duration(minutes: 30)), category: 'Sport', status: EventStatus.cancelled, registered: ['me']),
      ev('passe', start: DateTime(2026, 10, 1, 9, 0), category: 'Sport', registered: ['me']),
      ev('enCours', start: now.subtract(const Duration(minutes: 30)), category: 'Culture'),
    ];
    List<String> ids(List<EventModel> l) => l.map((e) => e.id).toList();

    test('À venir : sans annulés ni terminés, en cours inclus, trié par début', () {
      expect(ids(EventRules.filter(all, filter: EventFilter.upcoming, now: now)),
          ['enCours', 'futurSport1', 'futurCulture', 'futurSport2']);
    });
    test('Passés : seulement les terminés non annulés', () {
      expect(ids(EventRules.filter(all, filter: EventFilter.past, now: now)), ['passe']);
    });
    test('Mes inscriptions : tout, y compris annulés et passés', () {
      expect(ids(EventRules.filter(all, filter: EventFilter.myRegistrations, now: now, userId: 'me')),
          ['passe', 'futurSport1', 'annule']);
    });
    test('Mes événements', () {
      expect(ids(EventRules.filter(all, filter: EventFilter.myEvents, now: now, userId: 'me')), ['futurCulture']);
    });
    test('Mes inscriptions sans utilisateur : vide', () {
      expect(EventRules.filter(all, filter: EventFilter.myRegistrations, now: now), isEmpty);
    });
    test('À venir + catégorie', () {
      expect(ids(EventRules.filter(all, filter: EventFilter.upcoming, now: now, category: 'Sport')),
          ['futurSport1', 'futurSport2']);
    });
    test('À venir + jour (corrige eventsOnDay)', () {
      expect(ids(EventRules.filter(all, filter: EventFilter.upcoming, now: now, day: DateTime(2026, 11, 1))),
          ['futurSport1', 'futurCulture']);
    });
    test('À venir + jour + catégorie', () {
      expect(
          ids(EventRules.filter(all,
              filter: EventFilter.upcoming, now: now, day: DateTime(2026, 11, 1), category: 'Culture')),
          ['futurCulture']);
    });
    test('Mes inscriptions + catégorie + jour', () {
      expect(
          ids(EventRules.filter(all,
              filter: EventFilter.myRegistrations,
              now: now,
              userId: 'me',
              category: 'Sport',
              day: DateTime(2026, 11, 1))),
          ['futurSport1', 'annule']);
    });
    test('À venir + catégorie + recherche', () {
      expect(
          ids(EventRules.filter(all,
              filter: EventFilter.upcoming, now: now, category: 'Sport', query: 'evenement FUTURSPORT2')),
          ['futurSport2']);
    });
    test('aucun résultat : liste vide', () {
      expect(EventRules.filter(all, filter: EventFilter.past, now: now, category: 'Culture'), isEmpty);
    });
  });
}
