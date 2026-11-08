import 'package:campusconnect/models/event_model.dart';
import 'package:campusconnect/screens/evenements/ticket_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Le billet doit rester lisible sur petit écran et en grand texte, sans
/// débordement (bande jaune et noire).
void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  EventModel ev({EventStatus status = EventStatus.active, List<String> paid = const [], List<String> present = const []}) =>
      EventModel(
        id: 'evt-123',
        organizerId: 'org',
        organizerName: 'Club',
        title: 'Grande soirée de rentrée des clubs et associations du campus',
        description: 'Description',
        category: 'Vie associative',
        startDate: DateTime(2026, 11, 10, 18, 0),
        location: 'Esplanade centrale, bâtiment B, ESPRIT Ghazela, Ariana',
        price: 12.5,
        registeredUserIds: const ['stud1'],
        paidUserIds: paid,
        checkedInUserIds: present,
        status: status,
      );

  Future<void> pump(WidgetTester tester, EventModel event, {double width = 320, double textScale = 1.0}) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 1400), textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: TicketView(event: event, uid: 'stud1', studentName: 'Yasmine Ben Salah Trabelsi'),
        ),
      ),
    ));
  }

  testWidgets('320 px, texte ×1,3 : aucun débordement, puces lisibles', (tester) async {
    await pump(tester, ev(paid: ['stud1'], present: ['stud1']), textScale: 1.3);
    expect(tester.takeException(), isNull);
    expect(find.text('Payé ✓'), findsOneWidget);
    expect(find.text('Présent ✓'), findsOneWidget);
  });

  testWidgets('à payer sur place, pas encore présent', (tester) async {
    await pump(tester, ev());
    expect(tester.takeException(), isNull);
    expect(find.text('À payer sur place'), findsOneWidget);
    expect(find.text('Présent ✓'), findsNothing);
  });

  testWidgets('annulé : billet « Annulé », sans puce de paiement', (tester) async {
    await pump(tester, ev(status: EventStatus.cancelled), textScale: 1.3);
    expect(tester.takeException(), isNull);
    expect(find.text('BILLET ANNULÉ'), findsOneWidget);
    expect(find.text('Annulé'), findsOneWidget);
    expect(find.text('À payer sur place'), findsNothing);
  });

  testWidgets('le QR a un libellé pour les lecteurs d’écran', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, ev());
    expect(find.bySemanticsLabel(RegExp('Code QR du billet de Yasmine')), findsOneWidget);
    handle.dispose();
  });
}
