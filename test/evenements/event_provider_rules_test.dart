import 'package:campusconnect/core/constants/app_constants.dart';
import 'package:campusconnect/models/event_model.dart';
import 'package:campusconnect/providers/event_provider.dart';
import 'package:campusconnect/screens/evenements/event_actor.dart';
import 'package:campusconnect/screens/evenements/event_categories.dart';
import 'package:campusconnect/services/auth_service.dart';
import 'package:campusconnect/services/local_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/local_db.dart';

/// Règles que vérifiait l'ancien serveur (firestore.rules) et que le
/// provider vérifie maintenant lui-même, sur la version enregistrée et avec
/// l'identité de la session : elles tiennent même si l'écran est contourné.
void main() {
  late LocalStore store;
  late EventProvider provider;
  const col = AppConstants.eventsCollection;

  /// Ouvre une vraie session sur le téléphone (mêmes clés qu'AuthService).
  Future<void> signIn(String uid, {bool admin = false, bool disabled = false, bool twoFactorPending = false}) async {
    await store.set(AuthService.accountsCollection, uid, {'email': '$uid@esprit.tn'});
    await store.set(AppConstants.usersCollection, uid, {
      'fullName': 'Compte $uid',
      'email': '$uid@esprit.tn',
      'role': admin ? 'admin' : 'student',
      'disabled': disabled,
    });
    await store.setValue(AuthService.sessionKey, uid);
    await store.setValue(AuthService.twoFactorPendingKey, twoFactorPending ? '1' : null);
  }

  Future<void> signOut() => store.setValue(AuthService.sessionKey, null);

  final inThreeDays = DateTime.now().add(const Duration(days: 3));

  EventModel draft({
    String id = 'e1',
    String organizerId = 'org',
    String title = 'Atelier Flutter',
    String description = 'Un atelier pour découvrir Flutter',
    String location = 'Salle B12',
    String category = EventCategories.conference,
    DateTime? start,
    DateTime? end,
    int? capacity,
    double? price,
    double? latitude,
    double? longitude,
    String? posterUrl,
    List<String> registered = const [],
    EventStatus status = EventStatus.active,
  }) {
    final s = start ?? inThreeDays;
    return EventModel(
      id: id,
      organizerId: organizerId,
      organizerName: 'Club',
      title: title,
      description: description,
      category: category,
      startDate: s,
      endDate: end ?? s.add(const Duration(hours: 2)),
      location: location,
      latitude: latitude,
      longitude: longitude,
      capacity: capacity,
      price: price,
      posterUrl: posterUrl,
      registeredUserIds: registered,
      status: status,
    );
  }

  EventModel stored(String id) => EventModel.fromMap(id, store.get(col, id)!);

  /// Enregistre directement (sans passer par les règles), comme une donnée existante.
  Future<void> seed(EventModel e) => store.set(col, e.id, e.toMap());

  Matcher refused([Object? message]) => throwsA(isA<EventActionException>()
      .having((e) => e.message, 'message', message == null ? anything : (message is Matcher ? message : contains(message))));

  setUp(() async {
    await openTestDatabase();
    store = LocalStore();
    provider = EventProvider(store: store); // identité lue dans la session enregistrée
    await signIn('org');
  });

  tearDown(closeTestDatabase);

  group('identité lue dans la session (pas dans l\'écran)', () {
    test('session ouverte : uid et rôle du profil', () async {
      expect(EventActor.fromStore(store)!.uid, 'org');
      expect(EventActor.fromStore(store)!.isAdmin, isFalse);
      await signIn('chef', admin: true);
      expect(EventActor.fromStore(store)!.isAdmin, isTrue);
    });

    test('pas de session, double authentification en attente ou compte désactivé : visiteur', () async {
      await signOut();
      expect(EventActor.fromStore(store), isNull);
      await signIn('u2fa', twoFactorPending: true);
      expect(EventActor.fromStore(store), isNull);
      await signIn('banni', disabled: true);
      expect(EventActor.fromStore(store), isNull);
    });

    test('visiteur : ni création, ni modification', () async {
      await seed(draft());
      await signOut();
      expect(() => provider.createEvent(draft(id: 'x')), refused('Connectez-vous'));
      expect(() => provider.updateEvent(draft(), draft(title: 'Autre titre')), refused('Connectez-vous'));
    });
  });

  group('création', () {
    test('valide : enregistrée, createdAt = updatedAt', () async {
      await provider.createEvent(draft());
      final e = stored('e1');
      expect(e.organizerId, 'org');
      expect(e.createdAt, e.updatedAt);
    });

    test('organisateur différent de la personne connectée : refusée', () async {
      expect(() => provider.createEvent(draft(organizerId: 'quelqu-un')), refused("L'organisateur"));
      expect(store.exists(col, 'e1'), isFalse);
    });

    test('chaque champ est vérifié comme par l\'ancien serveur', () async {
      final invalid = {
        'titre court': draft(title: 'AB'),
        'titre sans lettre': draft(title: '1234'),
        'description courte': draft(description: 'Court'),
        'lieu court': draft(location: 'B'),
        'ancienne catégorie': draft(category: 'Job Fair'),
        'catégorie inconnue': draft(category: 'Atelier'),
        'fin avant le début': draft(end: inThreeDays.subtract(const Duration(hours: 1))),
        'plus de 72 h': draft(end: inThreeDays.add(const Duration(hours: 73))),
        'capacité 0': draft(capacity: 0),
        'capacité 5001': draft(capacity: 5001),
        'prix négatif': draft(price: -1),
        'prix > 1000': draft(price: 1000.5),
        'prix à 3 décimales': draft(price: 12.345),
        'coordonnées incomplètes': draft(latitude: 36.8),
        'coordonnées impossibles': draft(latitude: 120, longitude: 10),
        'affiche ftp': draft(posterUrl: 'ftp://exemple.tn/a.jpg'),
        'affiche relative': draft(posterUrl: 'events/a.jpg'),
        'affiche trop longue': draft(posterUrl: 'https://exemple.tn/${'a' * 500}'),
        'début dans 5 min': draft(start: DateTime.now().add(const Duration(minutes: 5))),
        'début à plus d\'un an': draft(start: DateTime.now().add(const Duration(days: 400))),
        'déjà annulé': draft(status: EventStatus.cancelled),
        'déjà des inscrits': draft(registered: ['u1']),
      };
      for (final entry in invalid.entries) {
        await expectLater(provider.createEvent(entry.value), refused(), reason: entry.key);
        expect(store.exists(col, 'e1'), isFalse, reason: entry.key);
      }
    });

    test('affiche acceptée : fichier du téléphone, image embarquée ou https', () async {
      final refs = [
        '/data/user/0/com.esprit.campusconnect/app_flutter/events/e1/a.jpg',
        r'C:\Users\amel\Documents\events\e2\a.jpg',
        'asset:assets/images/demo/team.jpg',
        'https://images.exemple.tn/affiche.jpg',
      ];
      for (var i = 0; i < refs.length; i++) {
        await provider.createEvent(draft(id: 'p$i', title: 'Atelier $i', posterUrl: refs[i]));
        expect(stored('p$i').posterUrl, refs[i]);
      }
    });

    test('doublon (même titre à la casse près, même début) : refusé', () async {
      await provider.createEvent(draft());
      expect(() => provider.createEvent(draft(id: 'e2', title: '  atelier   FLUTTER ')), refused('déjà créé'));
    });

    test('limite douce : 5 créations par jour et par organisateur', () async {
      for (var i = 0; i < 5; i++) {
        await provider.createEvent(draft(id: 'd$i', title: 'Atelier numéro $i'));
      }
      expect(() => provider.createEvent(draft(id: 'd5', title: 'Atelier numéro 5')), refused('5 événements'));
      // Une autre personne n'est pas concernée.
      await signIn('autre');
      await provider.createEvent(draft(id: 'a1', organizerId: 'autre', title: 'Atelier numéro 6'));
    });

    test('nouvel essai avec le même id : rien n\'est réécrit, createdAt du premier gardé', () async {
      await provider.createEvent(draft());
      final first = stored('e1');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await provider.createEvent(draft(title: 'Titre changé entre-temps'));
      expect(stored('e1').createdAt, first.createdAt);
      expect(stored('e1').title, 'Atelier Flutter');
      expect(store.all(col), hasLength(1));
    });

    test('id déjà pris par l\'événement d\'un autre : refusé, l\'autre est intact', () async {
      await seed(draft(organizerId: 'autre', title: 'Événement de quelqu\'un'));
      expect(() => provider.createEvent(draft()), refused('identifiant'));
      expect(stored('e1').organizerId, 'autre');
    });
  });

  group('modification', () {
    test('par quelqu\'un d\'autre que l\'organisateur : refusée', () async {
      await seed(draft());
      await signIn('etudiant');
      expect(() => provider.updateEvent(draft(), draft(title: 'Piraté')), refused("Seul l'organisateur"));
      expect(stored('e1').title, 'Atelier Flutter');
    });

    test('par un admin : acceptée', () async {
      await seed(draft());
      await signIn('chef', admin: true);
      await provider.updateEvent(draft(), draft(title: 'Modéré par l\'admin'));
      expect(stored('e1').title, 'Modéré par l\'admin');
    });

    test('terminé ou annulé : refusée', () async {
      final past = draft(start: DateTime.now().subtract(const Duration(hours: 5)));
      await seed(past);
      expect(() => provider.updateEvent(past, draft(title: 'Trop tard')), refused('terminé'));
      await seed(draft(id: 'c', status: EventStatus.cancelled));
      expect(() => provider.updateEvent(draft(id: 'c'), draft(id: 'c', title: 'Réactivé ?')), refused('annulé'));
    });

    test('contenu final invalide : refusé', () async {
      await seed(draft());
      expect(() => provider.updateEvent(draft(), draft(description: 'Court')), refused());
      expect(() => provider.updateEvent(draft(), draft(price: 2000)), refused());
      expect(() => provider.updateEvent(draft(), draft(posterUrl: 'ftp://x')), refused('Affiche'));
    });

    test('début déplacé dans moins de 15 minutes : refusé ; début inchangé proche : titre modifiable', () async {
      await seed(draft());
      final soon = DateTime.now().add(const Duration(minutes: 5));
      expect(() => provider.updateEvent(draft(), draft(start: soon)), refused('15 minutes'));

      final close = draft(id: 'proche', start: DateTime.now().add(const Duration(minutes: 10)));
      await seed(close);
      await provider.updateEvent(close, draft(id: 'proche', start: close.startDate, title: 'Titre corrigé'));
      expect(stored('proche').title, 'Titre corrigé');
    });

    test('organisateur, inscrits, présents, payés et statut ne sont jamais écrits par une modification', () async {
      await seed(draft(price: 10, registered: ['u1']));
      final edited = EventModel.fromMap('e1', {
        ...draft(price: 10, registered: ['u1']).toMap(),
        'title': 'Nouveau titre',
        'organizerId': 'pirate',
        'registeredUserIds': ['u1', 'u2', 'u3'],
        'checkedInUserIds': ['u1'],
        'paidUserIds': ['u1'],
        'status': 'cancelled',
      });
      await provider.updateEvent(draft(price: 10, registered: ['u1']), edited);
      final e = stored('e1');
      expect(e.title, 'Nouveau titre');
      expect(e.organizerId, 'org');
      expect(e.registeredUserIds, ['u1']);
      expect(e.checkedInUserIds, isEmpty);
      expect(e.paidUserIds, isEmpty);
      expect(e.status, EventStatus.active);
    });
  });
}
