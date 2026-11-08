import 'package:campusconnect/models/event_model.dart';
import 'package:campusconnect/screens/evenements/event_categories.dart';
import 'package:campusconnect/screens/evenements/event_rules.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Étape 13 : nouvelles catégories (avec traduction des anciennes) et prix.
void main() {
  final start = DateTime(2026, 11, 10, 14, 0);
  final now = DateTime(2026, 10, 19, 10, 0);

  EventModel ev({
    String id = 'e',
    String category = 'Sport',
    double? price,
    List<String> registered = const [],
  }) =>
      EventModel(
        id: id,
        organizerId: 'org',
        organizerName: 'Club',
        title: 'Événement $id',
        description: 'Description',
        category: category,
        startDate: start,
        location: 'Hall',
        price: price,
        registeredUserIds: registered,
      );

  group('catégories : source unique et traduction des anciennes valeurs', () {
    test('exactement les 5 nouvelles catégories', () {
      expect(EventCategories.all, ['Conférence', 'Carrière', 'Sport', 'Culture', 'Vie associative']);
    });
    test('valeurs actuelles gardées', () {
      for (final c in EventCategories.all) {
        expect(EventCategories.normalize(c), c);
      }
    });
    test('anciennes valeurs traduites', () {
      expect(EventCategories.normalize('Job Fair'), 'Carrière');
      expect(EventCategories.normalize('Associatif'), 'Vie associative');
      expect(EventCategories.normalize('Générale'), 'Conférence');
    });
    test('inconnue ou absente → Conférence', () {
      expect(EventCategories.normalize('Gaming'), 'Conférence');
      expect(EventCategories.normalize(null), 'Conférence');
      expect(EventCategories.normalize(''), 'Conférence');
    });
    test('fromMap applique la traduction (aucune migration)', () {
      Map<String, dynamic> doc(Object? category) => {
            'title': 'Ancien',
            'description': 'Document ancien',
            'location': 'Hall',
            'startDate': Timestamp.fromDate(start),
            'category': category,
          };
      expect(EventModel.fromMap('a', doc('Job Fair')).category, 'Carrière');
      expect(EventModel.fromMap('b', doc('Associatif')).category, 'Vie associative');
      expect(EventModel.fromMap('c', doc(null)).category, 'Conférence');
      expect(EventModel.fromMap('d', doc(42)).category, 'Conférence'); // valeur bizarre : pas de plantage
    });
  });

  group('prix : modèle', () {
    test('ancien document sans prix : gratuit (null)', () {
      final e = EventModel.fromMap('old', {
        'title': 'Ancien',
        'description': 'Document ancien',
        'category': 'Sport',
        'location': 'Stade',
        'startDate': Timestamp.fromDate(start),
      });
      expect(e.price, isNull);
      expect(EventRules.isFree(e), isTrue);
    });
    test('prix entier stocké (15) relu en double', () {
      final e = EventModel.fromMap('p', {...ev().toMap(), 'price': 15});
      expect(e.price, 15.0);
    });
    test('toMap / fromMap gardent le prix', () {
      expect(EventModel.fromMap('p', ev(price: 12.5).toMap()).price, 12.5);
      expect(ev(price: 12.5).toMap()['price'], 12.5);
    });
    test('copyWith : changer ou effacer le prix', () {
      expect(ev(price: 10).copyWith(price: 20).price, 20);
      expect(ev(price: 10).copyWith(clearPrice: true).price, isNull);
      expect(ev(price: 10).copyWith(title: 'Autre').price, 10);
    });
    test('changedFieldsSince : le prix fait partie des champs modifiables', () {
      final original = ev(price: 10);
      expect(original.copyWith(price: 15).changedFieldsSince(original), {'price': 15.0});
      expect(original.copyWith(clearPrice: true).changedFieldsSince(original), {'price': null});
      expect(EventModel.editableFields, contains('price'));
    });
  });

  group('prix : règles pures', () {
    test('isFree : null ou 0', () {
      expect(EventRules.isFree(ev()), isTrue);
      expect(EventRules.isFree(ev(price: 0)), isTrue);
      expect(EventRules.isFree(ev(price: 0.5)), isFalse);
    });
    test('priceLabel : Gratuit, entier, décimales avec virgule', () {
      expect(EventRules.priceLabel(ev()), 'Gratuit');
      expect(EventRules.priceLabel(ev(price: 0)), 'Gratuit');
      expect(EventRules.priceLabel(ev(price: 15)), '15 TND');
      expect(EventRules.priceLabel(ev(price: 12.5)), '12,50 TND');
      expect(EventRules.priceLabel(ev(price: 1000)), '1000 TND');
    });
    test('priceChanged : null et 0 comptent comme gratuit', () {
      expect(EventRules.priceChanged(null, 0), isFalse);
      expect(EventRules.priceChanged(null, null), isFalse);
      expect(EventRules.priceChanged(10, 10), isFalse);
      expect(EventRules.priceChanged(null, 5), isTrue);
      expect(EventRules.priceChanged(10, null), isTrue);
    });
    test('confirmation seulement si prix changé ET inscrits', () {
      expect(EventRules.needsPriceChangeConfirmation(ev(price: 10, registered: ['a']), 15), isTrue);
      expect(EventRules.needsPriceChangeConfirmation(ev(price: 10, registered: ['a']), 10), isFalse);
      expect(EventRules.needsPriceChangeConfirmation(ev(price: 10), 15), isFalse); // personne d'inscrit
      expect(EventRules.needsPriceChangeConfirmation(ev(registered: ['a']), 0), isFalse); // reste gratuit
    });
  });

  group('filtre de prix combiné', () {
    final all = [
      ev(id: 'gratuitSport', category: 'Sport'),
      ev(id: 'zeroCulture', category: 'Culture', price: 0),
      ev(id: 'payantSport', category: 'Sport', price: 15),
      ev(id: 'payantCulture', category: 'Culture', price: 8.5),
    ];
    List<String> ids(List<EventModel> l) => l.map((e) => e.id).toList()..sort();

    test('Tous : rien n’est filtré', () {
      expect(EventRules.filter(all, filter: EventFilter.upcoming, now: now).length, 4);
    });
    test('Gratuit : prix null ou 0', () {
      expect(ids(EventRules.filter(all, filter: EventFilter.upcoming, now: now, price: PriceFilter.free)),
          ['gratuitSport', 'zeroCulture']);
    });
    test('Payant', () {
      expect(ids(EventRules.filter(all, filter: EventFilter.upcoming, now: now, price: PriceFilter.paid)),
          ['payantCulture', 'payantSport']);
    });
    test('Payant + catégorie', () {
      expect(
          ids(EventRules.filter(all,
              filter: EventFilter.upcoming, now: now, price: PriceFilter.paid, category: 'Sport')),
          ['payantSport']);
    });
    test('le filtre de prix compte dans le badge des filtres actifs', () {
      expect(EventRules.activeFilterCount(price: PriceFilter.free), 1);
      expect(EventRules.activeFilterCount(category: 'Sport', price: PriceFilter.paid), 2);
      expect(EventRules.activeFilterCount(), 0);
    });
  });
}
