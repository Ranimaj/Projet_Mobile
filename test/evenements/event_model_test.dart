import 'package:campusconnect/models/event_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests sans Firebase : on ne touche jamais FirebaseFirestore.instance,
/// Timestamp est une simple classe de données.
void main() {
  final start = DateTime(2026, 11, 10, 14, 0);
  final end = DateTime(2026, 11, 10, 16, 0);

  EventModel event({
    int? capacity,
    List<String> registered = const [],
    EventStatus status = EventStatus.active,
  }) =>
      EventModel(
        id: 'e1',
        organizerId: 'org',
        organizerName: 'Club',
        title: 'Conférence IA',
        description: 'Une description assez longue',
        category: 'Conférence',
        startDate: start,
        endDate: end,
        location: 'Amphi A',
        capacity: capacity,
        registeredUserIds: registered,
        status: status,
      );

  group('statusAt', () {
    test('avant le début : à venir', () {
      expect(event().statusAt(start.subtract(const Duration(minutes: 1))), EventDisplayStatus.upcoming);
    });

    test('exactement au début : en cours', () {
      expect(event().statusAt(start), EventDisplayStatus.ongoing);
    });

    test('une minute avant la fin : en cours', () {
      expect(event().statusAt(end.subtract(const Duration(minutes: 1))), EventDisplayStatus.ongoing);
    });

    test('exactement à la fin : terminé', () {
      expect(event().statusAt(end), EventDisplayStatus.finished);
    });

    test('après la fin : terminé', () {
      expect(event().statusAt(end.add(const Duration(days: 1))), EventDisplayStatus.finished);
    });

    test('capacité atteinte avant le début : complet', () {
      final e = event(capacity: 2, registered: ['a', 'b']);
      expect(e.statusAt(start.subtract(const Duration(hours: 1))), EventDisplayStatus.full);
    });

    test('une place restante : à venir', () {
      final e = event(capacity: 2, registered: ['a']);
      expect(e.statusAt(start.subtract(const Duration(hours: 1))), EventDisplayStatus.upcoming);
    });

    test('complet mais commencé : en cours (le temps passe avant la capacité)', () {
      final e = event(capacity: 1, registered: ['a']);
      expect(e.statusAt(start), EventDisplayStatus.ongoing);
    });

    test('sans capacité : jamais complet', () {
      final e = event(registered: List.generate(1000, (i) => 'u$i'));
      expect(e.statusAt(start.subtract(const Duration(hours: 1))), EventDisplayStatus.upcoming);
    });

    test('annulé gagne sur tout (avant, pendant, après, complet)', () {
      final e = event(status: EventStatus.cancelled, capacity: 1, registered: ['a']);
      expect(e.statusAt(start.subtract(const Duration(hours: 1))), EventDisplayStatus.cancelled);
      expect(e.statusAt(start), EventDisplayStatus.cancelled);
      expect(e.statusAt(end.add(const Duration(days: 1))), EventDisplayStatus.cancelled);
    });
  });

  group('fromMap : valeurs par défaut des anciens documents', () {
    final oldDoc = <String, dynamic>{
      'organizerId': 'org',
      'organizerName': 'Club',
      'title': 'Ancien',
      'description': 'Document créé avant la v2',
      'category': 'Sport',
      'startDate': Timestamp.fromDate(start),
      'location': 'Stade',
      'registeredUserIds': ['a'],
    };

    test('champs v2 absents → défauts', () {
      final e = EventModel.fromMap('old', oldDoc);
      expect(e.startDate, start);
      expect(e.endDate, start.add(const Duration(hours: 2)));
      expect(e.capacity, isNull);
      expect(e.status, EventStatus.active);
      expect(e.cancelReason, isNull);
      expect(e.cancelledAt, isNull);
      expect(e.checkedInUserIds, isEmpty);
      expect(e.createdAt, start);
      expect(e.updatedAt, start);
      expect(e.registeredUserIds, ['a']);
    });

    test('document vide → ne plante pas', () {
      final e = EventModel.fromMap('empty', {});
      expect(e.title, '');
      expect(e.registeredUserIds, isEmpty);
      expect(e.endDate, e.startDate.add(const Duration(hours: 2)));
    });

    test('statut inconnu → actif ; "cancelled" → annulé', () {
      expect(EventModel.fromMap('x', {...oldDoc, 'status': 'bizarre'}).status, EventStatus.active);
      expect(EventModel.fromMap('x', {...oldDoc, 'status': 'cancelled'}).status, EventStatus.cancelled);
    });

    test('date acceptée sous 4 formes : Timestamp, DateTime, int, String', () {
      DateTime parsed(dynamic v) => EventModel.fromMap('x', {...oldDoc, 'startDate': v}).startDate;
      expect(parsed(Timestamp.fromDate(start)), start);
      expect(parsed(start), start);
      expect(parsed(start.millisecondsSinceEpoch), start);
      expect(parsed(start.toIso8601String()), start);
      expect(parsed(start.toUtc().toIso8601String()), start); // UTC « Z » → heure locale
    });

    test('capacité stockée en double (ex. 50.0) → int', () {
      expect(EventModel.fromMap('x', {...oldDoc, 'capacity': 50.0}).capacity, 50);
    });
  });

  group('toMap / fromMap aller-retour', () {
    test('tous les champs v2 sont conservés', () {
      final original = EventModel(
        id: 'e1',
        organizerId: 'org',
        organizerName: 'Club',
        title: 'Titre',
        description: 'Description assez longue',
        category: 'Culture',
        startDate: start,
        endDate: end,
        location: 'Hall',
        capacity: 30,
        status: EventStatus.cancelled,
        cancelReason: 'Salle indisponible',
        cancelledAt: DateTime(2026, 11, 1, 9, 0),
        checkedInUserIds: const ['a'],
        registeredUserIds: const ['a', 'b'],
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 2),
      );
      final copy = EventModel.fromMap('e1', original.toMap());
      expect(copy.endDate, end);
      expect(copy.capacity, 30);
      expect(copy.status, EventStatus.cancelled);
      expect(copy.cancelReason, 'Salle indisponible');
      expect(copy.cancelledAt, DateTime(2026, 11, 1, 9, 0));
      expect(copy.checkedInUserIds, ['a']);
      expect(copy.registeredUserIds, ['a', 'b']);
      expect(copy.createdAt, DateTime(2026, 10, 1));
      expect(copy.updatedAt, DateTime(2026, 10, 2));
      expect(original.toMap()['status'], 'cancelled');
      expect(original.toMap()['endDate'], isA<Timestamp>());
    });
  });

  group('copyWith / copyWithRegistration', () {
    final full = EventModel(
      id: 'e1',
      organizerId: 'org',
      organizerName: 'Club',
      title: 'Titre',
      description: 'Description',
      category: 'Sport',
      startDate: start,
      endDate: end,
      location: 'Stade',
      latitude: 36.8,
      longitude: 10.2,
      posterUrl: 'https://exemple/affiche.jpg',
      capacity: 10,
      checkedInUserIds: const ['z'],
      registeredUserIds: const ['a'],
      createdAt: DateTime(2026, 10, 1),
      updatedAt: DateTime(2026, 10, 2),
      pendingSync: true,
    );

    void expectSameExceptRegistrations(EventModel a, EventModel b) {
      expect(a.toMap()..remove('registeredUserIds'), b.toMap()..remove('registeredUserIds'));
      expect(a.pendingSync, b.pendingSync);
    }

    test('inscription : ajoute et garde tous les autres champs', () {
      final r = full.copyWithRegistration('b', true);
      expect(r.registeredUserIds, ['a', 'b']);
      expectSameExceptRegistrations(r, full);
    });

    test('inscription en double : pas de doublon', () {
      expect(full.copyWithRegistration('a', true).registeredUserIds, ['a']);
    });

    test('désinscription : retire et garde tous les autres champs', () {
      final r = full.copyWithRegistration('a', false);
      expect(r.registeredUserIds, isEmpty);
      expectSameExceptRegistrations(r, full);
    });

    test('copyWith change seulement ce qui est demandé', () {
      final c = full.copyWith(title: 'Nouveau');
      expect(c.title, 'Nouveau');
      expect(c.capacity, 10);
      expect(c.organizerId, 'org');
    });

    test('clearCapacity remet la capacité à illimitée', () {
      expect(full.copyWith(clearCapacity: true).capacity, isNull);
    });
  });
}
