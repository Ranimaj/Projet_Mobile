import 'package:campusconnect/core/constants/app_constants.dart';
import 'package:campusconnect/models/event_model.dart';
import 'package:campusconnect/providers/event_provider.dart';
import 'package:campusconnect/screens/evenements/event_actor.dart';
import 'package:campusconnect/screens/evenements/event_categories.dart';
import 'package:campusconnect/services/local_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/local_db.dart';

/// EventProvider sur la base locale (SQLite en mémoire) : chaque action
/// relit la version enregistrée, vérifie les règles, puis écrit.
void main() {
  late LocalStore store;
  late EventProvider provider;
  const col = AppConstants.eventsCollection;

  /// Personne connectée vue par le provider : l'organisateur par défaut ;
  /// les tests d'inscription agissent au nom de l'étudiant concerné.
  EventActor? actingAs;

  final start = DateTime.now().add(const Duration(days: 3));

  EventModel event({
    String id = 'e1',
    int? capacity,
    double? price,
    List<String> registered = const [],
    DateTime? startDate,
  }) =>
      EventModel(
        id: id,
        organizerId: 'org',
        organizerName: 'Club',
        title: 'Atelier',
        description: 'Un atelier pour tous',
        // Catégorie de la liste : la création vérifie de nouveau le contenu.
        category: EventCategories.conference,
        startDate: startDate ?? start,
        location: 'Salle B12',
        capacity: capacity,
        price: price,
        registeredUserIds: registered,
      );

  EventModel stored(String id) => EventModel.fromMap(id, store.get(col, id)!);

  Future<void> seed(EventModel e) async {
    await store.set(col, e.id, e.toMap());
    await provider.load();
  }

  setUp(() async {
    await openTestDatabase();
    store = LocalStore();
    actingAs = const EventActor('org');
    provider = EventProvider(store: store, actor: () => actingAs);
  });

  tearDown(closeTestDatabase);

  group('lecture', () {
    test('load lit les événements enregistrés', () async {
      await store.set(col, 'a', event(id: 'a').toMap());
      await store.set(col, 'b', event(id: 'b').toMap());
      await provider.load();
      expect(provider.all.map((e) => e.id), unorderedEquals(['a', 'b']));
      expect(provider.loadError, isNull);
      expect(provider.isLoading, isFalse);
    });

    test('watchEvent : version actuelle, mises à jour, puis null après suppression', () async {
      await seed(event());
      final values = <EventModel?>[];
      final sub = provider.watchEvent('e1').listen(values.add);
      await pumpEventQueue();
      await store.merge(col, 'e1', {'title': 'Nouveau titre'});
      await pumpEventQueue();
      await store.delete(col, 'e1');
      await pumpEventQueue();
      await sub.cancel();

      expect(values.first?.title, 'Atelier');
      expect(values.any((e) => e?.title == 'Nouveau titre'), isTrue);
      expect(values.last, isNull);
      expect(provider.findById('e1'), isNull); // retiré de la liste
    });

    test('fonctionne hors-ligne : la connexion ne bloque rien', () async {
      actingAs = const EventActor('u1');
      provider.updateConnectivity(false);
      await seed(event());
      expect(await provider.toggleRegistrationWithResult(event(), 'u1'), isTrue);
      expect(provider.isOnline, isFalse);
    });
  });

  group('création / modification / annulation', () {
    test('createEvent enregistre le document avec createdAt = updatedAt', () async {
      await provider.createEvent(event(id: 'new'));
      final e = stored('new');
      expect(e.title, 'Atelier');
      expect(e.createdAt, e.updatedAt);
      expect(provider.findById('new'), isNotNull);
    });

    test('createEvent deux fois avec le même id : un seul document', () async {
      await provider.createEvent(event(id: 'same'));
      await provider.createEvent(event(id: 'same'));
      expect(store.all(col).where((d) => d.id == 'same'), hasLength(1));
    });

    test('updateEvent écrit seulement les champs changés : les inscriptions faites entre-temps restent', () async {
      final original = event();
      await seed(original);
      // Quelqu'un s'inscrit pendant que l'organisateur modifie.
      await store.merge(col, 'e1', {
        'registeredUserIds': ['u1']
      });

      await provider.updateEvent(original, original.copyWith(title: 'Atelier modifié'));
      final e = stored('e1');
      expect(e.title, 'Atelier modifié');
      expect(e.registeredUserIds, ['u1']);
      expect(DateTime.now().difference(e.updatedAt).inSeconds, lessThan(5)); // horloge du téléphone
    });

    test('updateEvent : capacité sous le nombre d’inscrits refusée', () async {
      final original = event(registered: ['u1', 'u2']);
      await seed(original);
      expect(
          () => provider.updateEvent(original, original.copyWith(capacity: 1)), throwsA(isA<EventActionException>()));
    });

    test('updateEvent : événement supprimé → « n’existe plus »', () async {
      final original = event();
      expect(() => provider.updateEvent(original, original.copyWith(title: 'X')),
          throwsA(isA<EventActionException>().having((e) => e.message, 'message', "Cet événement n'existe plus.")));
    });

    test('cancelEvent garde les inscriptions ; une 2e annulation est refusée', () async {
      final e = event(registered: ['u1']);
      await seed(e);
      await provider.cancelEvent(e, 'Salle indisponible');
      final saved = stored('e1');
      expect(saved.status, EventStatus.cancelled);
      expect(saved.cancelReason, 'Salle indisponible');
      expect(saved.cancelledAt, isNotNull);
      expect(saved.registeredUserIds, ['u1']);
      expect(() => provider.cancelEvent(e, 'Encore une fois'), throwsA(isA<EventActionException>()));
    });

    test('cancelEvent : motif trop court refusé', () async {
      await seed(event());
      expect(() => provider.cancelEvent(event(), 'non'), throwsA(isA<EventActionException>()));
      expect(stored('e1').status, EventStatus.active);
    });
  });

  group('suppression', () {
    test('organisateur : refusée s’il y a des inscrits (version enregistrée)', () async {
      await seed(event());
      await store.merge(col, 'e1', {
        'registeredUserIds': ['u1']
      }); // inscrit entre-temps
      expect(() => provider.deleteEvent(event(), isAdmin: false), throwsA(isA<EventHasRegistrantsException>()));
      expect(store.exists(col, 'e1'), isTrue);
    });

    test('organisateur sans inscrit, ou admin : supprimé', () async {
      await seed(event());
      await provider.deleteEvent(event(), isAdmin: false);
      expect(store.exists(col, 'e1'), isFalse);
      expect(provider.findById('e1'), isNull);

      await seed(event(id: 'e2', registered: ['u1']));
      await provider.deleteEvent(event(id: 'e2', registered: ['u1']), isAdmin: true);
      expect(store.exists(col, 'e2'), isFalse);
    });
  });

  group('inscription', () {
    // Chacun ne s'inscrit que lui-même : on agit au nom de « u1 ».
    setUp(() => actingAs = const EventActor('u1'));

    test('inscription puis désinscription', () async {
      await seed(event());
      expect(await provider.toggleRegistrationWithResult(event(), 'u1'), isTrue);
      expect(stored('e1').registeredUserIds, ['u1']);
      expect(await provider.toggleRegistrationWithResult(event(), 'u1'), isFalse);
      expect(stored('e1').registeredUserIds, isEmpty);
    });

    test('dernière place : la 2e personne voit l’événement complet', () async {
      await seed(event(capacity: 1));
      // Deux comptes en même temps, chacun avec sa copie locale (périmée).
      final other = EventProvider(store: store, actor: () => const EventActor('u2'));
      await other.load();
      final results = await Future.wait([
        provider.toggleRegistrationWithResult(event(capacity: 1), 'u1').then((r) => '$r', onError: (_) => 'refus'),
        other.toggleRegistrationWithResult(event(capacity: 1), 'u2').then((r) => '$r', onError: (_) => 'refus'),
      ]);
      expect(results, ['true', 'refus']);
      expect(stored('e1').registeredUserIds, ['u1']);
    });

    test('inscriptions simultanées sans capacité : aucune perdue', () async {
      await seed(event());
      final other = EventProvider(store: store, actor: () => const EventActor('u2'));
      await other.load();
      await Future.wait([
        provider.toggleRegistrationWithResult(event(), 'u1'),
        other.toggleRegistrationWithResult(event(), 'u2'),
      ]);
      expect(stored('e1').registeredUserIds, unorderedEquals(['u1', 'u2']));
    });

    test('double tap : le 2e est ignoré (null)', () async {
      await seed(event());
      final first = provider.toggleRegistrationWithResult(event(), 'u1');
      expect(await provider.toggleRegistrationWithResult(event(), 'u1'), isNull);
      expect(await first, isTrue);
    });

    test('non connecté : refusé', () async {
      await seed(event());
      expect(() => provider.toggleRegistrationWithResult(event(), null), throwsA(isA<EventActionException>()));
    });

    test('événement commencé : inscription refusée', () async {
      final past = event(startDate: DateTime.now().subtract(const Duration(minutes: 10)));
      await seed(past);
      expect(() => provider.toggleRegistrationWithResult(past, 'u1'), throwsA(isA<EventActionException>()));
    });

    test('désinscription : retiré aussi des présents et des payés', () async {
      await seed(event(price: 10, registered: ['u1', 'u2']));
      await store.merge(col, 'e1', {
        'checkedInUserIds': ['u1'],
        'paidUserIds': ['u1', 'u2'],
      });
      await provider.toggleRegistrationWithResult(event(), 'u1');
      final e = stored('e1');
      expect(e.registeredUserIds, ['u2']);
      expect(e.checkedInUserIds, isEmpty);
      expect(e.paidUserIds, ['u2']);
    });
  });

  group('pointage (organisateur)', () {
    test('payé : bascule ajout / retrait ; gratuit refusé', () async {
      await seed(event(price: 15, registered: ['u1']));
      await provider.togglePaid('e1', 'u1');
      expect(stored('e1').paidUserIds, ['u1']);
      await provider.togglePaid('e1', 'u1');
      expect(stored('e1').paidUserIds, isEmpty);

      await seed(event(id: 'free', registered: ['u1']));
      expect(() => provider.togglePaid('free', 'u1'), throwsA(isA<EventActionException>()));
    });

    test('présent : refusé plus d’1 h avant le début ; accepté pendant l’heure qui précède', () async {
      await seed(event(registered: ['u1']));
      expect(() => provider.togglePresent('e1', 'u1'), throwsA(isA<EventActionException>()));

      final soon = event(id: 'soon', registered: ['u1'], startDate: DateTime.now().add(const Duration(minutes: 30)));
      await seed(soon);
      await provider.markPresent('soon', 'u1');
      await provider.markPresent('soon', 'u1'); // scan répété : jamais retiré
      expect(stored('soon').checkedInUserIds, ['u1']);
      await provider.togglePresent('soon', 'u1');
      expect(stored('soon').checkedInUserIds, isEmpty);
    });

    test('pointage d’une personne non inscrite refusé', () async {
      await seed(event(price: 5, registered: ['u1']));
      expect(() => provider.togglePaid('e1', 'intrus'), throwsA(isA<EventActionException>()));
    });

    test('noms des inscrits lus dans les comptes enregistrés', () async {
      await store.set(AppConstants.usersCollection, 'u1', {'fullName': ' Amira Ben Ali '});
      await store.set(AppConstants.usersCollection, 'u2', {'fullName': ''});
      final names = await provider.attendeeNames(['u1', 'u2', 'inconnu']);
      expect(names, {'u1': 'Amira Ben Ali'});
    });
  });
}
