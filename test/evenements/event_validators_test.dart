import 'package:campusconnect/models/event_model.dart';
import 'package:campusconnect/screens/evenements/event_validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // « Maintenant » fixe : les tests ne dépendent pas de l'horloge réelle.
  final now = DateTime(2026, 10, 19, 10, 0);

  group('normalize', () {
    test('supprime les espaces autour et réduit les espaces répétés', () {
      expect(EventValidators.normalize('  Soirée    Jazz  '), 'Soirée Jazz');
    });
    test('garde les retours à la ligne', () {
      expect(EventValidators.normalize('Ligne 1\nLigne   2'), 'Ligne 1\nLigne 2');
    });
    test('null → chaîne vide', () {
      expect(EventValidators.normalize(null), '');
    });
  });

  group('titre (3 à 80, au moins une lettre)', () {
    test('valide', () => expect(EventValidators.title('Hackathon'), isNull));
    test('vide ou null', () {
      expect(EventValidators.title(''), isNotNull);
      expect(EventValidators.title(null), isNotNull);
    });
    test('espaces seulement', () => expect(EventValidators.title('      '), isNotNull));
    test('2 caractères refusé, 3 accepté', () {
      expect(EventValidators.title('AB'), isNotNull);
      expect(EventValidators.title('ABC'), isNull);
    });
    test('80 accepté, 81 refusé', () {
      expect(EventValidators.title('a' * 80), isNull);
      expect(EventValidators.title('a' * 81), isNotNull);
    });
    test('longueur mesurée après normalisation', () {
      expect(EventValidators.title('  A  B  '), isNull); // devient "A B" (3)
    });
    test('sans lettre refusé', () {
      expect(EventValidators.title('2026'), 'Le titre doit contenir au moins une lettre');
      expect(EventValidators.title('!!!'), isNotNull);
    });
    test('lettre accentuée acceptée', () => expect(EventValidators.title('À 20h'), isNull));
  });

  group('description (10 à 1000)', () {
    test('9 refusé, 10 accepté', () {
      expect(EventValidators.description('a' * 9), isNotNull);
      expect(EventValidators.description('a' * 10), isNull);
    });
    test('1000 accepté, 1001 refusé', () {
      expect(EventValidators.description('a' * 1000), isNull);
      expect(EventValidators.description('a' * 1001), isNotNull);
    });
    test('vide refusé', () => expect(EventValidators.description('   '), isNotNull));
  });

  group('lieu (3 à 100)', () {
    test('2 refusé, 3 accepté', () {
      expect(EventValidators.location('ab'), isNotNull);
      expect(EventValidators.location('Hal'), isNull);
    });
    test('100 accepté, 101 refusé', () {
      expect(EventValidators.location('a' * 100), isNull);
      expect(EventValidators.location('a' * 101), isNotNull);
    });
  });

  group('catégorie', () {
    test('les 5 nouvelles catégories sont valides', () {
      for (final c in ['Conférence', 'Carrière', 'Sport', 'Culture', 'Vie associative']) {
        expect(EventValidators.category(c), isNull, reason: c);
      }
    });
    test('anciennes valeurs refusées à la création / modification', () {
      for (final c in ['Job Fair', 'Associatif', 'Générale']) {
        expect(EventValidators.category(c), 'Catégorie invalide', reason: c);
      }
    });
    test('inconnue ou null refusée', () {
      expect(EventValidators.category('Gaming'), 'Catégorie invalide');
      expect(EventValidators.category(null), 'Catégorie invalide');
    });
  });

  group('prix (optionnel, 0 à 1000 TND, 2 décimales max)', () {
    test('vide = gratuit : valide, enregistré null', () {
      expect(EventValidators.price(''), isNull);
      expect(EventValidators.price(null), isNull);
      expect(EventValidators.price('   '), isNull);
      expect(EventValidators.parsePrice(''), isNull);
    });
    test('entier, 1 ou 2 décimales : valides', () {
      expect(EventValidators.price('15'), isNull);
      expect(EventValidators.price('12.5'), isNull);
      expect(EventValidators.price('12.50'), isNull);
    });
    test('virgule acceptée et normalisée', () {
      expect(EventValidators.price('12,5'), isNull);
      expect(EventValidators.parsePrice('12,5'), 12.5);
    });
    test('3 décimales refusées', () {
      expect(EventValidators.price('12.505'), 'Prix entre 0 et 1000 TND (2 décimales max)');
      expect(EventValidators.price('12,505'), isNotNull);
    });
    test('négatif refusé', () => expect(EventValidators.price('-5'), isNotNull));
    test('0 et 1000 acceptés ; 1000.01 refusé', () {
      expect(EventValidators.price('0'), isNull);
      expect(EventValidators.price('1000'), isNull);
      expect(EventValidators.price('1000.00'), isNull);
      expect(EventValidators.price('1000.01'), isNotNull);
    });
    test('texte refusé', () {
      expect(EventValidators.price('abc'), isNotNull);
      expect(EventValidators.price('12.'), isNotNull);
      expect(EventValidators.price('.5'), isNotNull);
      expect(EventValidators.price('1,2,3'), isNotNull);
    });
    test('arrondi à 2 décimales avant l’enregistrement', () {
      expect(EventValidators.parsePrice('19.99'), 19.99);
      expect(EventValidators.parsePrice('0,10'), 0.1);
      expect(EventValidators.parsePrice('15'), 15.0);
    });
  });

  group('début (≥ 15 min, ≤ 365 jours)', () {
    test('dans 1 jour : valide', () {
      expect(EventValidators.start(now.add(const Duration(days: 1)), now: now), isNull);
    });
    test('dans 5 min : refusé', () {
      expect(EventValidators.start(now.add(const Duration(minutes: 5)), now: now), isNotNull);
    });
    test('exactement 15 min : accepté ; 14 min : refusé', () {
      expect(EventValidators.start(now.add(const Duration(minutes: 15)), now: now), isNull);
      expect(EventValidators.start(now.add(const Duration(minutes: 14)), now: now), isNotNull);
    });
    test("aujourd'hui avec une heure passée : refusé", () {
      expect(EventValidators.start(DateTime(2026, 10, 19, 8, 0), now: now),
          "L'événement doit commencer dans le futur");
    });
    test('365 jours : accepté ; 366 jours : refusé', () {
      expect(EventValidators.start(now.add(const Duration(days: 365)), now: now), isNull);
      expect(EventValidators.start(now.add(const Duration(days: 366)), now: now), isNotNull);
    });
    test('null refusé', () => expect(EventValidators.start(null, now: now), isNotNull));
  });

  group('fin (après le début, 15 min à 72 h)', () {
    final s = DateTime(2026, 11, 1, 14, 0);
    test('2 h : valide', () => expect(EventValidators.end(s, s.add(const Duration(hours: 2))), isNull));
    test('avant le début : refusé', () {
      expect(EventValidators.end(s, s.subtract(const Duration(hours: 1))), isNotNull);
    });
    test('égale au début : refusé', () => expect(EventValidators.end(s, s), isNotNull));
    test('15 min accepté ; 14 min refusé', () {
      expect(EventValidators.end(s, s.add(const Duration(minutes: 15))), isNull);
      expect(EventValidators.end(s, s.add(const Duration(minutes: 14))), isNotNull);
    });
    test('72 h accepté ; 72 h 01 refusé', () {
      expect(EventValidators.end(s, s.add(const Duration(hours: 72))), isNull);
      expect(EventValidators.end(s, s.add(const Duration(hours: 72, minutes: 1))), isNotNull);
    });
    test('valeur manquante refusée', () {
      expect(EventValidators.end(null, s), isNotNull);
      expect(EventValidators.end(s, null), isNotNull);
    });
  });

  group('capacité (optionnelle, 1 à 5000, ≥ inscrits)', () {
    test('vide = illimitée : valide', () {
      expect(EventValidators.capacity(''), isNull);
      expect(EventValidators.capacity(null), isNull);
      expect(EventValidators.capacity('   '), isNull);
    });
    test('0 et 5001 refusés ; 1 et 5000 acceptés', () {
      expect(EventValidators.capacity('0'), 'Entre 1 et 5000');
      expect(EventValidators.capacity('5001'), isNotNull);
      expect(EventValidators.capacity('1'), isNull);
      expect(EventValidators.capacity('5000'), isNull);
    });
    test('pas un entier refusé', () {
      expect(EventValidators.capacity('abc'), isNotNull);
      expect(EventValidators.capacity('12.5'), isNotNull);
      expect(EventValidators.capacity('-3'), isNotNull);
    });
    test('modification : pas sous le nombre d’inscrits', () {
      expect(EventValidators.capacity('7', registeredCount: 8), 'Entre 1 et 5000 (minimum : 8 inscrits)');
      expect(EventValidators.capacity('8', registeredCount: 8), isNull);
    });
  });

  group('affiche (JPG/PNG, ≤ 5 Mo)', () {
    test('pas d’affiche : valide', () => expect(EventValidators.poster(), isNull));
    test('jpg, jpeg, PNG acceptés', () {
      expect(EventValidators.poster(fileName: 'a.jpg', sizeBytes: 1000), isNull);
      expect(EventValidators.poster(fileName: 'a.jpeg', sizeBytes: 1000), isNull);
      expect(EventValidators.poster(fileName: 'A.PNG', sizeBytes: 1000), isNull);
    });
    test('gif ou pdf refusé', () {
      expect(EventValidators.poster(fileName: 'a.gif', sizeBytes: 1000), isNotNull);
      expect(EventValidators.poster(fileName: 'a.pdf', sizeBytes: 1000), isNotNull);
    });
    test('5 Mo accepté, 5 Mo + 1 octet refusé', () {
      expect(EventValidators.poster(fileName: 'a.jpg', sizeBytes: 5 * 1024 * 1024), isNull);
      expect(EventValidators.poster(fileName: 'a.jpg', sizeBytes: 5 * 1024 * 1024 + 1), isNotNull);
    });
  });

  group('coordonnées', () {
    test('absentes : valide (géocodage raté)', () => expect(EventValidators.coordinates(null, null), isNull));
    test('Tunis : valide', () => expect(EventValidators.coordinates(36.8, 10.18), isNull));
    test('limites incluses', () {
      expect(EventValidators.coordinates(90, 180), isNull);
      expect(EventValidators.coordinates(-90, -180), isNull);
    });
    test('hors limites refusé', () {
      expect(EventValidators.coordinates(90.1, 0), isNotNull);
      expect(EventValidators.coordinates(0, -180.1), isNotNull);
    });
    test('une seule coordonnée refusée', () => expect(EventValidators.coordinates(36.8, null), isNotNull));
  });

  EventModel existing({
    String id = 'e1',
    String organizerId = 'org',
    String title = 'Soirée Jazz',
    DateTime? start,
    DateTime? createdAt,
  }) =>
      EventModel(
        id: id,
        organizerId: organizerId,
        organizerName: 'Club',
        title: title,
        description: 'Description',
        category: 'Culture',
        startDate: start ?? DateTime(2026, 11, 1, 20, 0),
        location: 'Hall',
        createdAt: createdAt,
      );

  group('modification bloquée (terminé ou annulé)', () {
    final s = DateTime(2026, 11, 1, 20, 0);
    final e = existing(start: s); // fin par défaut : s + 2 h
    test('à venir : modifiable', () {
      expect(EventValidators.editBlocked(e, s.subtract(const Duration(days: 1))), isNull);
    });
    test('en cours : modifiable', () => expect(EventValidators.editBlocked(e, s), isNull));
    test('terminé : refusé', () {
      expect(EventValidators.editBlocked(e, s.add(const Duration(hours: 2))),
          'Un événement terminé ne peut plus être modifié.');
    });
    test('annulé : refusé', () {
      final cancelled = e.copyWith(status: EventStatus.cancelled);
      expect(EventValidators.editBlocked(cancelled, s.subtract(const Duration(days: 1))),
          'Un événement annulé ne peut plus être modifié.');
    });
  });

  group('doublon (même organisateur, titre normalisé, début)', () {
    final list = [existing()];
    test('même titre avec casse et espaces différents : refusé', () {
      expect(
          EventValidators.duplicate(
              organizerId: 'org', title: '  soirée   JAZZ ', start: DateTime(2026, 11, 1, 20, 0), existing: list),
          isNotNull);
    });
    test('autre organisateur : accepté', () {
      expect(
          EventValidators.duplicate(
              organizerId: 'autre', title: 'Soirée Jazz', start: DateTime(2026, 11, 1, 20, 0), existing: list),
          isNull);
    });
    test('autre heure : accepté', () {
      expect(
          EventValidators.duplicate(
              organizerId: 'org', title: 'Soirée Jazz', start: DateTime(2026, 11, 1, 21, 0), existing: list),
          isNull);
    });
    test('en modification, l’événement lui-même est ignoré', () {
      expect(
          EventValidators.duplicate(
              organizerId: 'org',
              title: 'Soirée Jazz',
              start: DateTime(2026, 11, 1, 20, 0),
              existing: list,
              ignoreId: 'e1'),
          isNull);
    });
  });

  group('limite de 5 créations par jour', () {
    List<EventModel> createdToday(int n, {String organizerId = 'org'}) => [
          for (var i = 0; i < n; i++)
            existing(id: 'e$i', organizerId: organizerId, createdAt: DateTime(2026, 10, 19, 8, i)),
        ];

    test('4 aujourd’hui : encore autorisé', () {
      expect(EventValidators.dailyLimit(organizerId: 'org', existing: createdToday(4), now: now), isNull);
    });
    test('5 aujourd’hui : refusé', () {
      expect(EventValidators.dailyLimit(organizerId: 'org', existing: createdToday(5), now: now), isNotNull);
    });
    test('créations d’hier ou d’un autre organisateur non comptées', () {
      final list = [
        ...createdToday(5, organizerId: 'autre'),
        for (var i = 0; i < 5; i++) existing(id: 'y$i', createdAt: DateTime(2026, 10, 18, 9, i)),
      ];
      expect(EventValidators.dailyLimit(organizerId: 'org', existing: list, now: now), isNull);
    });
  });
}
