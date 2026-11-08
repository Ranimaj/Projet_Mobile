import 'package:campusconnect/models/event_model.dart';
import 'package:campusconnect/screens/evenements/event_hero_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Écran étroit : la carte « Prochain événement » ne doit jamais déborder
/// (bande jaune et noire « RIGHT OVERFLOWED »). Un débordement est signalé
/// comme une exception de rendu : takeException() la récupère.
void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  final now = DateTime(2026, 10, 19, 10, 0);
  // Cas défavorable : la catégorie la plus longue et des textes longs.
  final event = EventModel(
    id: 'e1',
    organizerId: 'org',
    organizerName: 'Club',
    title: 'Grande soirée de rentrée des clubs et associations du campus',
    description: 'Description',
    category: 'Vie associative',
    startDate: DateTime(2026, 11, 2, 18, 30),
    location: 'Esplanade centrale, bâtiment B, ESPRIT Ghazela, Ariana',
    price: 12.5,
  );

  Future<void> pumpCard(WidgetTester tester, {required double width, double textScale = 1.0}) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800), textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: SingleChildScrollView(
            // Même marge latérale que la liste (20 px de chaque côté).
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: EventHeroCard(event: event, now: now),
          ),
        ),
      ),
    ));
  }

  testWidgets('320 px de large : aucun débordement', (tester) async {
    await pumpCard(tester, width: 320);
    expect(tester.takeException(), isNull);
    expect(find.text('dans 14 jours'), findsOneWidget); // la pastille reste entière
  });

  testWidgets('360 px et texte agrandi (×1,3) : aucun débordement', (tester) async {
    await pumpCard(tester, width: 360, textScale: 1.3);
    expect(tester.takeException(), isNull);
  });

  testWidgets('le libellé de l’en-tête est sur une ligne, avec « … »', (tester) async {
    await pumpCard(tester, width: 320);
    final label = tester.widget<Text>(find.text('PROCHAIN ÉVÉNEMENT · VIE ASSOCIATIVE'));
    expect(label.maxLines, 1);
    expect(label.overflow, TextOverflow.ellipsis);
  });
}
