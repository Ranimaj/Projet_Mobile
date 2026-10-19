import 'package:campusconnect/models/event_model.dart';
import 'package:campusconnect/screens/evenements/event_calendar_sync.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Logique pure de la synchronisation calendrier : aucun téléphone, aucun plugin.
void main() {
  final start = DateTime(2026, 11, 10, 18, 0);
  final end = DateTime(2026, 11, 10, 21, 30); // 3 h 30 : pas les « 2 h » d'avant

  EventModel event({EventStatus status = EventStatus.active, String organizer = 'Club Robotique'}) => EventModel(
        id: 'e1',
        organizerId: 'org',
        organizerName: organizer,
        title: '  Soirée robots  ',
        description: 'Démonstrations et ateliers.',
        category: 'Associatif',
        startDate: start,
        endDate: end,
        location: ' Hall principal ',
        status: status,
      );

  group('buildEntry', () {
    final entry = EventCalendarSync.buildEntry(event());

    test('vraies dates de début et de fin', () {
      expect(entry.start, start);
      expect(entry.end, end);
    });
    test('titre et lieu sans espaces autour', () {
      expect(entry.title, 'Soirée robots');
      expect(entry.location, 'Hall principal');
    });
    test('rappel de 30 minutes avant', () => expect(entry.alarmMinutes, 30));
    test('description : catégorie, organisateur puis texte', () {
      expect(entry.description, startsWith('Associatif · organisé par Club Robotique'));
      expect(entry.description, contains('Démonstrations et ateliers.'));
    });
    test('organisateur vide : libellé de repli', () {
      expect(EventCalendarSync.descriptionText(event(organizer: '  ')), contains('organisé par organisateur inconnu'));
    });
    test('ancien document sans date de fin : valeur par défaut du modèle (début + 2 h)', () {
      final legacy = EventModel.fromMap('old', {
        'title': 'Ancien',
        'description': 'Sans date de fin',
        'category': 'Sport',
        'location': 'Stade',
        'startDate': Timestamp.fromDate(start),
      });
      final e = EventCalendarSync.buildEntry(legacy);
      expect(e.end, start.add(const Duration(hours: 2)));
    });
  });

  group('refus et remarque', () {
    test('événement annulé : refusé avec un message clair', () {
      expect(EventCalendarSync.blockedReason(event(status: EventStatus.cancelled)),
          'Événement annulé : il ne peut pas être ajouté au calendrier.');
    });
    test('événement actif : autorisé', () => expect(EventCalendarSync.blockedReason(event()), isNull));
    test('terminé : autorisé, avec une remarque « pour mémoire »', () {
      expect(EventCalendarSync.note(event(), end), 'Événement déjà terminé : ajouté pour mémoire.');
      expect(EventCalendarSync.blockedReason(event()), isNull);
    });
    test('à venir ou en cours : pas de remarque', () {
      expect(EventCalendarSync.note(event(), start.subtract(const Duration(days: 1))), isNull);
      expect(EventCalendarSync.note(event(), start), isNull);
    });
  });
}
