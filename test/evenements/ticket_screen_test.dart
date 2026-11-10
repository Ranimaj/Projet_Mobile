import 'package:campusconnect/models/event_model.dart';
import 'package:campusconnect/screens/evenements/ticket_link.dart';
import 'package:campusconnect/screens/evenements/ticket_rules.dart';
import 'package:campusconnect/screens/evenements/ticket_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:qr_flutter/qr_flutter.dart';

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

  group('lisibilité de la carte (fond blanc dans les deux thèmes)', () {
    const eventId = '3b70c2e1-9f4d-4c1a-8a77-5e2f10d4b9aa';
    const uid = '3da7f0b2-1c6e-4e8d-b1f3-7a9c2d5e8f01';

    Future<void> pumpThemed(WidgetTester tester, ThemeData theme, EventModel event,
        {Size size = const Size(320, 1400), double textScale = 1.0}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: MediaQuery(
          data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
          child: Scaffold(body: TicketView(event: event, uid: uid, studentName: 'Yasmine Ben Salah Trabelsi')),
        ),
      ));
    }

    EventModel withIds({double price = 12.5, List<String> paid = const [], EventStatus status = EventStatus.active}) =>
        EventModel(
          status: status,
          id: eventId,
          organizerId: 'org',
          organizerName: 'Club',
          title: 'Grande soirée de rentrée',
          description: 'Description',
          category: 'Vie associative',
          startDate: DateTime(2026, 11, 10, 18, 0),
          location: 'Esplanade centrale',
          price: price,
          registeredUserIds: const [uid],
          paidUserIds: paid,
        );

    TextStyle styleOf(WidgetTester tester, Finder text) =>
        tester.widget<RichText>(find.descendant(of: text, matching: find.byType(RichText)).first).text.style!;

    /// Tous les textes de la carte, sauf la bande d'en-tête (blanc sur la
    /// couleur de catégorie, inchangée).
    Iterable<RichText> cardTexts(WidgetTester tester) => tester
        .widgetList<RichText>(find.descendant(of: find.byKey(const Key('ticket-card')), matching: find.byType(RichText)))
        .where((r) => !r.text.toPlainText().startsWith('BILLET'));

    for (final (name, theme) in [('clair', ThemeData.light()), ('sombre', ThemeData.dark())]) {
      testWidgets('thème $name : chaque texte de la carte a un contraste ≥ 4,5:1, titre en avant', (tester) async {
        await pumpThemed(tester, theme, withIds(paid: [uid]));
        expect(tester.takeException(), isNull);

        final texts = cardTexts(tester).toList();
        expect(texts.length, greaterThanOrEqualTo(7));
        for (final r in texts) {
          final color = r.text.style?.color;
          expect(color, isNotNull, reason: r.text.toPlainText());
          expect(TicketColors.contrast(color!, TicketView.cardColor), greaterThanOrEqualTo(4.5),
              reason: '« ${r.text.toPlainText()} » : $color');
        }

        final title = styleOf(tester, find.byKey(const Key('ticket-title')));
        expect(TicketColors.contrast(title.color!, TicketView.cardColor), greaterThanOrEqualTo(7));
        expect(title.fontWeight, FontWeight.w800);
        for (final r in texts) {
          if (r.text.toPlainText() == 'Grande soirée de rentrée' || r.text.toPlainText() == 'ANNULÉ') continue;
          expect(r.text.style!.fontSize!, lessThan(title.fontSize!), reason: r.text.toPlainText());
        }
      });
    }

    testWidgets('thème sombre, billet annulé : le tampon reste lisible', (tester) async {
      await pumpThemed(tester, ThemeData.dark(), withIds(status: EventStatus.cancelled));
      final stamp = styleOf(tester, find.text('ANNULÉ'));
      expect(TicketColors.contrast(stamp.color!, TicketView.cardColor), greaterThanOrEqualTo(4.5));
    });

    testWidgets('la référence sous le QR reprend les identifiants du QR', (tester) async {
      await pumpThemed(tester, ThemeData.light(), withIds());
      final ticket = TicketRules.parseTicketPayload(TicketRules.buildTicketPayload(eventId, uid))!;
      final expected =
          'Billet n° ${ticket.eventId.substring(0, 4).toUpperCase()}-${ticket.uid.substring(0, 4).toUpperCase()}';
      expect(expected, 'Billet n° 3B70-3DA7');
      expect(find.text(expected), findsOneWidget);
      // Sous le QR.
      expect(tester.getTopLeft(find.byKey(const Key('ticket-reference'))).dy,
          greaterThan(tester.getBottomLeft(find.byType(QrImageView)).dy));
      expect(TicketView.reference('demo-amel', 'u1'), 'Billet n° DEMO-U1');
    });

    testWidgets('le QR contient l’adresse du billet, dont le fragment est « CC1|eventId|uid »', (tester) async {
      await pumpThemed(tester, ThemeData.light(), withIds());
      final link = TicketLink.build(withIds(), uid, 'Yasmine Ben Salah Trabelsi');
      expect(link, startsWith('${TicketRules.billetBaseUrl}#${Uri.encodeComponent('CC1|$eventId|$uid')}?'));
      final ticket = TicketRules.parseTicketPayload(link)!;
      expect((ticket.eventId, ticket.uid), (eventId, uid));

      final shown = tester.widget<CustomPaint>(
          find.descendant(of: find.byType(QrImageView), matching: find.byType(CustomPaint)).first);
      final painter = shown.painter! as QrPainter;
      // Correction d'erreur basse : QR le moins dense possible.
      expect(painter.errorCorrectionLevel, QrErrorCorrectLevel.L);
      QrPainter reference(String data) => QrPainter(
            data: data,
            version: QrVersions.auto,
            errorCorrectionLevel: painter.errorCorrectionLevel,
            gapless: painter.gapless,
            eyeStyle: painter.eyeStyle,
            dataModuleStyle: painter.dataModuleStyle,
          );

      final (actual, same, other) = (await tester.runAsync(() async => (
            (await painter.toImageData(200))!.buffer.asUint8List(),
            (await reference(link).toImageData(200))!.buffer.asUint8List(),
            (await reference(link.replaceFirst(uid, 'autre')).toImageData(200))!.buffer.asUint8List(),
          )))!;
      expect(actual, same);
      expect(actual, isNot(other));
    });

    testWidgets('gratuit : « Gratuit » n’apparaît qu’une fois (la puce)', (tester) async {
      await pumpThemed(tester, ThemeData.light(), withIds(price: 0));
      expect(find.text('Gratuit'), findsOneWidget);
      expect(find.byIcon(Icons.sell_outlined), findsNothing);
    });

    testWidgets('payant : la ligne de prix reste', (tester) async {
      await pumpThemed(tester, ThemeData.light(), withIds());
      expect(find.byIcon(Icons.sell_outlined), findsOneWidget);
      expect(find.text('À payer sur place'), findsOneWidget);
    });

    for (final theme in [ThemeData.light(), ThemeData.dark()]) {
      testWidgets('320×568, texte ×1,5 (${theme.brightness.name}) : aucun débordement', (tester) async {
        await pumpThemed(tester, theme, withIds(paid: [uid]), size: const Size(320, 568), textScale: 1.5);
        expect(tester.takeException(), isNull);
        await tester.dragUntilVisible(
            find.text('Payé ✓'), find.byType(Scrollable).first, const Offset(0, -200));
        expect(tester.takeException(), isNull);
      });
    }
  });
}
