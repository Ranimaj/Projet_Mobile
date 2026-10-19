import 'package:campusconnect/models/event_model.dart';
import 'package:campusconnect/screens/evenements/event_card.dart';
import 'package:campusconnect/screens/evenements/event_hero_card.dart';
import 'package:campusconnect/screens/evenements/event_rules.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Étape 16 : « Près de moi » (distance, tri) et affichage de la distance.
void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  const tunis = (lat: 36.8065, lng: 10.1815);

  EventModel ev(String id, {double? lat, double? lng, DateTime? start}) => EventModel(
        id: id,
        organizerId: 'org',
        organizerName: 'Club',
        title: 'Événement $id',
        description: 'Description',
        category: 'Sport',
        startDate: start ?? DateTime(2026, 11, 10, 18, 0),
        location: 'Lieu $id',
        latitude: lat,
        longitude: lng,
      );

  group('haversine', () {
    test('même point : 0 km', () => expect(EventRules.haversineKm(36.8, 10.18, 36.8, 10.18), 0));
    test('1° de latitude ≈ 111,2 km', () {
      expect(EventRules.haversineKm(36, 10, 37, 10), closeTo(111.19, 0.05));
    });
    test('Tunis centre → Ariana centre : environ 6 à 8 km à vol d’oiseau', () {
      final km = EventRules.haversineKm(36.8065, 10.1815, 36.8625, 10.1956);
      expect(km, inInclusiveRange(5.5, 8.5));
    });
    test('Tunis → Sousse ≈ 115 km', () {
      expect(EventRules.haversineKm(36.8065, 10.1815, 35.8256, 10.6084), closeTo(115, 3));
    });
    test('symétrique', () {
      expect(EventRules.haversineKm(36.8, 10.1, 35.8, 10.6), closeTo(EventRules.haversineKm(35.8, 10.6, 36.8, 10.1), 1e-9));
    });
    test('distanceMeters : null sans coordonnées', () {
      expect(EventRules.distanceMeters(ev('x'), tunis), isNull);
      expect(EventRules.distanceMeters(ev('y', lat: 36.8065, lng: 10.1815), tunis), 0);
    });
  });

  group('tri « Près de moi »', () {
    test('du plus proche au plus loin, puis les non localisés par date', () {
      final list = EventRules.sortByDistance([
        ev('sousse', lat: 35.8256, lng: 10.6084),
        ev('sansLieuTard', start: DateTime(2026, 11, 20)),
        ev('ariana', lat: 36.8625, lng: 10.1956),
        ev('sansLieuTot', start: DateTime(2026, 11, 5)),
        ev('centre', lat: 36.8070, lng: 10.1820),
      ], tunis);
      expect(list.map((e) => e.id), ['centre', 'ariana', 'sousse', 'sansLieuTot', 'sansLieuTard']);
    });
    test('même distance : le plus tôt d’abord', () {
      final list = EventRules.sortByDistance([
        ev('tard', lat: 36.9, lng: 10.2, start: DateTime(2026, 12, 1)),
        ev('tot', lat: 36.9, lng: 10.2, start: DateTime(2026, 11, 1)),
      ], tunis);
      expect(list.map((e) => e.id), ['tot', 'tard']);
    });
    test('aucun événement localisé : simplement par date', () {
      final list = EventRules.sortByDistance([
        ev('b', start: DateTime(2026, 11, 2)),
        ev('a', start: DateTime(2026, 11, 1)),
      ], tunis);
      expect(list.map((e) => e.id), ['a', 'b']);
    });
    test('liste vide : liste vide', () => expect(EventRules.sortByDistance([], tunis), isEmpty));
  });

  group('distance affichée (320 px, texte ×1,3)', () {
    Future<void> pump(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(320, 900), textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 20), child: child),
          ),
        ),
      ));
    }

    final longEvent = EventModel(
      id: 'e',
      organizerId: 'org',
      organizerName: 'Club',
      title: 'Grande soirée de rentrée des clubs et associations du campus',
      description: 'Description',
      category: 'Vie associative',
      startDate: DateTime(2026, 11, 10, 18, 0),
      location: 'Esplanade centrale, bâtiment B, ESPRIT Ghazela, Ariana',
      capacity: 120,
      price: 12.5,
    );

    testWidgets('carte : « 3,2 km » sans débordement', (tester) async {
      await pump(tester, EventCard(event: longEvent, now: DateTime(2026, 10, 19), isRegistered: true, distanceMeters: 3240));
      expect(tester.takeException(), isNull);
      expect(find.text('3,2 km'), findsOneWidget);
    });

    testWidgets('carte sans tri « Près de moi » : pas de distance', (tester) async {
      await pump(tester, EventCard(event: longEvent, now: DateTime(2026, 10, 19), isRegistered: false));
      expect(find.textContaining('km'), findsNothing);
    });

    testWidgets('carte « Prochain événement » : « 850 m » sans débordement', (tester) async {
      await pump(tester, EventHeroCard(event: longEvent, now: DateTime(2026, 10, 19), distanceMeters: 847));
      expect(tester.takeException(), isNull);
      expect(find.text('850 m'), findsOneWidget);
    });
  });
}
