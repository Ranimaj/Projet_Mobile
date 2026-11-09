import 'dart:convert';
import 'dart:io';

import 'package:campusconnect/core/theme/app_theme.dart';
import 'package:campusconnect/models/event_model.dart';
import 'package:campusconnect/providers/event_provider.dart';
import 'package:campusconnect/screens/evenements/add_event_screen.dart';
import 'package:campusconnect/screens/evenements/category_classifier.dart';
import 'package:campusconnect/screens/evenements/event_categories.dart';
import 'package:campusconnect/screens/evenements/photon_service.dart';
import 'package:campusconnect/screens/evenements/poster_ocr.dart';
import 'package:campusconnect/screens/evenements/poster_parser.dart';
import 'package:campusconnect/screens/evenements/poster_scan_sheets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'poster_fixtures.dart';

/// Faux lecteur : renvoie des lignes fixées (ou lève une erreur), sans ML Kit.
class FakePosterTextReader implements PosterTextReader {
  final PosterOcrResult? result;
  final Object? error;
  int calls = 0;
  FakePosterTextReader(this.result) : error = null;
  FakePosterTextReader.failing(this.error) : result = null;

  @override
  Future<PosterOcrResult> read(File image) async {
    calls++;
    if (error != null) throw error!;
    return result!;
  }
}

/// Photon factice : renvoie la réponse fixée et note les recherches.
class FakePhotonService extends PhotonService {
  final PhotonResponse response;
  final List<String> queries = [];
  FakePhotonService([this.response = const PhotonSuccess([])]);

  @override
  Future<PhotonResponse> search(String query) async {
    queries.add(query);
    return response;
  }
}

PosterOcrLine _l(String text, double top, double height) => PosterOcrLine(text, top: top, height: height);

/// Jour à venir (dans 30 jours), au format de l'affiche « jj/mm/aaaa ».
final DateTime _day = DateTime.now().add(const Duration(days: 30));
String get _dayText =>
    '${_day.day.toString().padLeft(2, '0')}/${_day.month.toString().padLeft(2, '0')}/${_day.year}';

/// Affiche « sport » : titre, date + heure, lieu, entrée libre, pied de page.
PosterOcrResult get _sportPoster => PosterOcrResult([
      _l('ESPRIT · VIE DE CAMPUS', 40, 14),
      _l('TOURNOI DE FOOTBALL INTER-CLASSES', 120, 64),
      _l('$_dayText à 14h30', 260, 30),
      _l("Lieu : Stade de l'ESPRIT, Ghazala", 310, 26),
      _l('Équipes de 7 joueurs · Entrée libre', 360, 24),
      _l('Club Sport ESPRIT', 760, 14),
    ]);

/// Fausse image : en-tête JPEG, sans dimensions lisibles.
XFile _image({String name = 'affiche.jpg'}) =>
    XFile.fromData(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0]), name: name, path: '/tmp/$name');

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));
  final classifier = CategoryClassifier.fromJson(
      jsonDecode(File('assets/ml/category_model.json').readAsStringSync()) as Map<String, dynamic>);

  final scanCard = find.text('Scanner une affiche');
  final titleField = find.widgetWithText(TextFormField, "Titre de l'événement");
  final descField = find.widgetWithText(TextFormField, 'Description');
  final placeField = find.widgetWithText(TextFormField, 'Lieu');
  final priceField = find.widgetWithText(TextFormField, 'Prix (TND)');
  final sheet = find.byType(PosterReviewSheet);
  Finder inSheet(String text) => find.descendant(of: sheet, matching: find.text(text));

  String textOf(WidgetTester tester, Finder field) =>
      tester.widget<EditableText>(find.descendant(of: field, matching: find.byType(EditableText))).controller.text;

  bool? checked(WidgetTester tester, String label) =>
      tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, label)).value;

  Future<void> pump(
    WidgetTester tester, {
    PosterTextReader? reader,
    Future<XFile?> Function(ImageSource)? pick,
    EventModel? existing,
    double width = 420,
    double textScale = 1.0,
    bool dark = false,
    PhotonService? photon,
  }) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // EventProvider : la recherche de lieu lit l'état du réseau ; Photon
    // factice : aucun appel réseau dans les tests.
    await tester.pumpWidget(ChangeNotifierProvider<EventProvider>(
      create: (_) => EventProvider(),
      child: MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: AddEventScreen(
        existing: existing,
        loadClassifier: () => SynchronousFuture(classifier),
        posterTextReader: reader ?? FakePosterTextReader(_sportPoster),
        pickScanImage: pick ?? (_) async => _image(),
        photonService: photon ?? FakePhotonService(),
      ),
    )));
    await tester.pump();
  }

  /// Carte → galerie → feuille de vérification ouverte.
  Future<void> scanFromGallery(WidgetTester tester) async {
    await tester.tap(scanCard);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choisir dans la galerie'));
    await tester.pumpAndSettle();
  }

  Future<void> apply(WidgetTester tester) async {
    await tester.ensureVisible(inSheet('Appliquer'));
    await tester.tap(inSheet('Appliquer'));
    await tester.pumpAndSettle();
  }

  /// Interrupteur « affiche » coupé : pas de compression pendant le test.
  Future<void> turnPosterOff(WidgetTester tester) async {
    final toggle = find.widgetWithText(SwitchListTile, "Utiliser cette image comme affiche de l'événement");
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pump();
  }

  group('point d\'entrée', () {
    testWidgets('carte visible en création, absente en modification', (tester) async {
      await pump(tester);
      expect(scanCard, findsOneWidget);
      expect(find.text("Remplit le formulaire à partir d'une photo ou d'une image"), findsOneWidget);

      await pump(tester,
          existing: EventModel(
            id: 'e1',
            organizerId: 'u1',
            organizerName: 'Amel',
            title: 'Tournoi',
            description: 'Un tournoi de football',
            category: EventCategories.sport,
            startDate: _day,
            location: 'Stade',
          ));
      expect(scanCard, findsNothing);
    });

    testWidgets('la feuille propose photo, galerie et annuler ; annuler ne fait rien', (tester) async {
      final reader = FakePosterTextReader(_sportPoster);
      await pump(tester, reader: reader);
      await tester.tap(scanCard);
      await tester.pumpAndSettle();
      expect(find.text('Prendre une photo'), findsOneWidget);
      expect(find.text('Choisir dans la galerie'), findsOneWidget);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(reader.calls, 0);
      expect(sheet, findsNothing);
    });

    testWidgets('caméra : la source demandée est bien la caméra', (tester) async {
      ImageSource? asked;
      await pump(tester, pick: (s) async {
        asked = s;
        return _image();
      });
      await tester.tap(scanCard);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prendre une photo'));
      await tester.pumpAndSettle();
      expect(asked, ImageSource.camera);
      expect(sheet, findsOneWidget);
    });

    testWidgets('sélection annulée : aucune lecture, aucune feuille', (tester) async {
      final reader = FakePosterTextReader(_sportPoster);
      await pump(tester, reader: reader, pick: (_) async => null);
      await scanFromGallery(tester);
      expect(reader.calls, 0);
      expect(sheet, findsNothing);
    });

    testWidgets('accès refusé : message et « Ouvrir les réglages »', (tester) async {
      await pump(tester, pick: (_) async => throw PlatformException(code: 'camera_access_denied'));
      await tester.tap(scanCard);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prendre une photo'));
      await tester.pump();
      expect(find.textContaining("Accès à l'appareil photo refusé"), findsOneWidget);
      expect(find.text('Ouvrir les réglages'), findsOneWidget);
    });

    testWidgets('lecture trop longue : message en français, formulaire intact', (tester) async {
      await pump(tester, reader: FakePosterTextReader.failing(const PosterReadException(PosterReadFailure.timeout)));
      await scanFromGallery(tester);
      expect(find.textContaining('trop de temps'), findsOneWidget);
      expect(sheet, findsNothing);
      expect(textOf(tester, titleField), isEmpty);
    });
  });

  group('feuille de vérification', () {
    testWidgets('liste les valeurs lues, cochées par défaut', (tester) async {
      await pump(tester);
      await scanFromGallery(tester);
      expect(find.text("Voici ce que j'ai lu"), findsOneWidget);
      expect(inSheet('Tournoi de football inter-classes'), findsOneWidget);
      expect(inSheet(PosterParser.formatDateTime(DateTime(_day.year, _day.month, _day.day, 14, 30))), findsOneWidget);
      expect(inSheet("Stade de l'ESPRIT, Ghazala"), findsOneWidget);
      expect(inSheet('Gratuit'), findsOneWidget);
      for (final label in ['Titre', 'Début', 'Lieu', 'Prix', 'Description']) {
        expect(checked(tester, label), isTrue, reason: label);
      }
      // Fin non lue : pas de case.
      expect(find.widgetWithText(CheckboxListTile, 'Fin'), findsNothing);
    });

    testWidgets('« Appliquer » remplit les champs cochés, sans afficher d\'erreur', (tester) async {
      await pump(tester);
      await scanFromGallery(tester);
      await turnPosterOff(tester);
      await apply(tester);

      expect(textOf(tester, titleField), 'Tournoi de football inter-classes');
      expect(textOf(tester, placeField), "Stade de l'ESPRIT, Ghazala");
      expect(textOf(tester, descField), 'Équipes de 7 joueurs · Entrée libre');
      expect(textOf(tester, priceField), isEmpty); // gratuit
      final start = DateTime(_day.year, _day.month, _day.day, 14, 30);
      expect(find.textContaining('Début :'), findsOneWidget);
      expect(
          tester.state<FormFieldState<DateTime>>(find.byType(FormField<DateTime>).first).value, start);
      expect(find.text("Champs préremplis : vérifiez avant d'enregistrer"), findsOneWidget);
      expect(find.textContaining('requis'), findsNothing);
      // Seulement le texte du lieu : pas de position, donc l'aide habituelle.
      expect(find.textContaining('Choisissez une suggestion'), findsOneWidget);
    });

    testWidgets('la puce de catégorie apparaît après « Appliquer » (texte rempli par le code)', (tester) async {
      await pump(tester);
      await scanFromGallery(tester);
      await turnPosterOff(tester);
      await apply(tester);
      await tester.pump(const Duration(milliseconds: 600));
      // Le libellé de la puce utilise des espaces insécables.
      expect(find.textContaining(RegExp(r'Suggestion\s:\sSport')), findsOneWidget);
    });

    testWidgets('un champ déjà saisi n\'est pas écrasé sauf si on le coche', (tester) async {
      await pump(tester);
      await tester.enterText(titleField, 'Mon titre');
      await tester.enterText(placeField, 'Salle 12');
      await scanFromGallery(tester);

      expect(checked(tester, 'Titre'), isFalse);
      expect(checked(tester, 'Lieu'), isFalse);
      expect(find.text('remplacerait la valeur actuelle'), findsNWidgets(2));
      await turnPosterOff(tester);
      await apply(tester);
      expect(textOf(tester, titleField), 'Mon titre');
      expect(textOf(tester, placeField), 'Salle 12');

      // Deuxième scan : on coche le titre, il est remplacé ; le lieu reste.
      await scanFromGallery(tester);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Titre'));
      await tester.pump();
      await turnPosterOff(tester);
      await apply(tester);
      expect(textOf(tester, titleField), 'Tournoi de football inter-classes');
      expect(textOf(tester, placeField), 'Salle 12');
    });

    testWidgets('description déjà remplie : la ligne Description n\'est pas proposée', (tester) async {
      await pump(tester);
      await tester.enterText(descField, 'Ma propre description');
      await scanFromGallery(tester);
      expect(inSheet('Description'), findsNothing);
    });

    group('description composée (affiche sans texte courant)', () {
      final when = DateTime(_day.year, _day.month, _day.day, 18);
      PosterOcrResult infoOnly() => PosterOcrResult([
            _l('NUIT DES JEUX', 300, 84),
            _l('$_dayText à 18h', 500, 46),
            _l('Lieu : Foyer, bloc B', 600, 44),
          ]);
      final composed = "Nuit des jeux · ${PosterParser.formatWhen(when)} · Foyer, bloc B";

      testWidgets('ligne « composée à partir des infos lues », cochée, remplit le champ', (tester) async {
        await pump(tester, reader: FakePosterTextReader(infoOnly()));
        await scanFromGallery(tester);
        expect(inSheet(posterComposedDescriptionLabel), findsOneWidget);
        expect(checked(tester, posterComposedDescriptionLabel), isTrue);
        expect(inSheet(composed), findsOneWidget);
        await turnPosterOff(tester);
        await apply(tester);
        expect(textOf(tester, descField), composed);
      });

      testWidgets('description déjà saisie : décochée et « remplacerait », gardée sans case cochée', (tester) async {
        await pump(tester, reader: FakePosterTextReader(infoOnly()));
        await tester.enterText(descField, 'Ma propre description');
        await scanFromGallery(tester);
        expect(checked(tester, posterComposedDescriptionLabel), isFalse);
        expect(find.text('remplacerait la valeur actuelle'), findsOneWidget);
        await turnPosterOff(tester);
        await apply(tester);
        expect(textOf(tester, descField), 'Ma propre description');
      });
    });

    testWidgets('date passée : avertissement, début inchangé', (tester) async {
      final past = DateTime.now().subtract(const Duration(days: 3));
      final text = '${past.day}/${past.month}/${past.year} à 10h';
      await pump(tester,
          reader: FakePosterTextReader(PosterOcrResult([_l('SOIRÉE JEUX', 50, 60), _l(text, 140, 28)])));
      final before = tester.state<FormFieldState<DateTime>>(find.byType(FormField<DateTime>).first).value;
      await scanFromGallery(tester);
      expect(find.textContaining('Date détectée dans le passé'), findsOneWidget);
      expect(find.widgetWithText(CheckboxListTile, 'Début'), findsNothing);
      await turnPosterOff(tester);
      await apply(tester);
      expect(tester.state<FormFieldState<DateTime>>(find.byType(FormField<DateTime>).first).value, before);
    });

    testWidgets('date sans heure : « (heure non lue) », pas de case, action « Choisir l\'heure »', (tester) async {
      await pump(tester,
          reader: FakePosterTextReader(PosterOcrResult([_l('SOIRÉE JEUX', 50, 60), _l(_dayText, 140, 28)])));
      await scanFromGallery(tester);
      expect(find.textContaining('(heure non lue)'), findsOneWidget);
      expect(find.widgetWithText(CheckboxListTile, 'Début'), findsNothing);
      await turnPosterOff(tester);
      await apply(tester);
      expect(find.text("Choisir l'heure"), findsOneWidget);

      await tester.tap(find.text("Choisir l'heure"));
      await tester.pumpAndSettle();
      // Le sélecteur de date s'ouvre sur le jour lu.
      expect(find.byType(DatePickerDialog), findsOneWidget);
      expect(tester.widget<DatePickerDialog>(find.byType(DatePickerDialog)).initialDate,
          DateTime(_day.year, _day.month, _day.day));
    });

    testWidgets('rien de lu : message, rappel « caractères latins », bouton Fermer', (tester) async {
      await pump(tester, reader: FakePosterTextReader(PosterOcrResult.empty));
      await scanFromGallery(tester);
      expect(find.text(posterNothingReadMessage), findsOneWidget);
      expect(find.text(PosterParser.latinOnlyWarning), findsOneWidget);
      expect(inSheet('Appliquer'), findsNothing);
      await tester.tap(inSheet('Fermer'));
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
    });
  });

  group('lieu lu : suggestions Photon après « Appliquer »', () {
    const stadium = PlaceSuggestion(
        name: 'Stade ESPRIT', label: 'Stade ESPRIT, Ariana', secondary: 'Ariana, Tunisie', latitude: 36.9, longitude: 10.19);
    const other = PlaceSuggestion(
        name: 'Stade olympique', label: 'Stade olympique, Radès', secondary: 'Radès, Tunisie', latitude: 36.75, longitude: 10.27);
    final hint = find.textContaining('Choisissez une suggestion');

    Future<void> scanApplyAndWait(WidgetTester tester) async {
      await scanFromGallery(tester);
      await turnPosterOff(tester);
      await apply(tester);
      await tester.pump(const Duration(milliseconds: 600)); // pause de 500 ms, comme à la saisie
      await tester.pump();
    }

    testWidgets('la liste habituelle apparaît, rien n\'est choisi d\'office', (tester) async {
      final photon = FakePhotonService(const PhotonSuccess([stadium, other]));
      await pump(tester, photon: photon);
      await scanApplyAndWait(tester);
      expect(photon.queries, ["Stade de l'ESPRIT, Ghazala"]);
      expect(find.text('Stade ESPRIT'), findsOneWidget);
      expect(find.text('Stade olympique'), findsOneWidget);
      expect(textOf(tester, placeField), "Stade de l'ESPRIT, Ghazala"); // texte lu gardé
      expect(hint, findsOneWidget); // pas encore localisé
      expect(find.text('Lieu localisé'), findsNothing);
    });

    testWidgets('toucher une suggestion localise le lieu (carte et itinéraire)', (tester) async {
      await pump(tester, photon: FakePhotonService(const PhotonSuccess([stadium])));
      await scanApplyAndWait(tester);
      await tester.ensureVisible(find.text('Stade ESPRIT'));
      await tester.tap(find.text('Stade ESPRIT'));
      await tester.pump();
      expect(textOf(tester, placeField), 'Stade ESPRIT, Ariana');
      expect(find.text('Lieu localisé'), findsWidgets);
      expect(hint, findsNothing);
    });

    testWidgets('aucun résultat : texte gardé, non localisé, formulaire utilisable', (tester) async {
      await pump(tester, photon: FakePhotonService(const PhotonSuccess([])));
      await scanApplyAndWait(tester);
      expect(find.textContaining('Aucun lieu trouvé'), findsOneWidget);
      expect(hint, findsOneWidget);
      expect(textOf(tester, titleField), 'Tournoi de football inter-classes');
      expect(tester.takeException(), isNull);
    });

    testWidgets('échec du service : pas de liste, pas d\'erreur, formulaire utilisable', (tester) async {
      await pump(tester,
          photon: FakePhotonService(const PhotonFailure(PhotonError.noConnection, 'Pas de connexion')));
      await scanApplyAndWait(tester);
      expect(find.textContaining('Aucun lieu trouvé'), findsNothing);
      expect(hint, findsOneWidget);
      expect(textOf(tester, placeField), "Stade de l'ESPRIT, Ghazala");
      expect(tester.takeException(), isNull);
    });

    testWidgets('lieu non coché dans la feuille : aucune recherche', (tester) async {
      final photon = FakePhotonService(const PhotonSuccess([stadium]));
      await pump(tester, photon: photon);
      await scanFromGallery(tester);
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Lieu'));
      await tester.pump();
      await turnPosterOff(tester);
      await apply(tester);
      await tester.pump(const Duration(milliseconds: 600));
      expect(photon.queries, isEmpty);
      expect(find.text('Stade ESPRIT'), findsNothing);
    });

    // Affiches synthétiques, dates avancées pour rester dans le futur.
    PosterOcrResult moved(PosterFixture fx, String dateLine) => PosterOcrResult([
          for (final l in fx.lines)
            RegExp(r'\d{4}').hasMatch(l.text) ? PosterOcrLine(dateLine, top: l.top, height: l.height, block: l.block) : l,
        ]);

    testWidgets('affiche synthétique « atelier » : recherche de son lieu, description composée', (tester) async {
      final photon = FakePhotonService(const PhotonSuccess([stadium]));
      await pump(tester,
          photon: photon, reader: FakePosterTextReader(moved(syntheticPosterFixtures[0], '$_dayText · 15h')));
      await scanApplyAndWait(tester);
      expect(photon.queries, ['Garage du foyer, bloc D']);
      expect(textOf(tester, descField), startsWith('Atelier réparation de vélos · '));
    });

    testWidgets('affiche synthétique « concert » (sans lieu) : aucune recherche, prix rempli', (tester) async {
      final photon = FakePhotonService(const PhotonSuccess([stadium]));
      await pump(tester, photon: photon, reader: FakePosterTextReader(moved(syntheticPosterFixtures[1], _dayText)));
      await scanApplyAndWait(tester);
      expect(photon.queries, isEmpty);
      expect(textOf(tester, priceField), '15');
      expect(textOf(tester, descField), endsWith(' · 15 TND'));
    });
  });

  group('affiche', () {
    testWidgets('interrupteur coupé : l\'image n\'est pas utilisée', (tester) async {
      await pump(tester);
      await scanFromGallery(tester);
      await turnPosterOff(tester);
      await apply(tester);
      expect(find.textContaining("L'image n'est pas gardée"), findsNothing);
      expect(find.text('Ajouter une affiche'), findsOneWidget);
    });

    testWidgets('image refusée (format) : champs remplis quand même, utilisateur prévenu', (tester) async {
      await pump(tester, pick: (_) async => _image(name: 'affiche.webp'));
      await scanFromGallery(tester);
      await apply(tester); // interrupteur activé par défaut
      expect(textOf(tester, titleField), 'Tournoi de football inter-classes');
      expect(find.textContaining("L'image n'est pas gardée comme affiche : Format non supporté"), findsOneWidget);
    });

    testWidgets('image acceptée par les règles : envoyée au circuit de compression habituel', (tester) async {
      await pump(tester);
      await scanFromGallery(tester);
      await apply(tester);
      // La fausse image n'a pas de dimensions lisibles : le compresseur la
      // refuse, preuve qu'elle a suivi le même chemin qu'une affiche choisie.
      expect(find.textContaining('Impossible de préparer cette image'), findsOneWidget);
    });
  });

  group('affichage étroit', () {
    for (final dark in [false, true]) {
      for (final scale in [1.5, 2.0]) {
        testWidgets('320 px, texte ×$scale, ${dark ? 'sombre' : 'clair'} : aucun débordement', (tester) async {
          await pump(tester, width: 320, textScale: scale, dark: dark);
          expect(tester.takeException(), isNull);
          await tester.tap(scanCard);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Choisir dans la galerie'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          // La feuille défile jusqu'aux boutons.
          await tester.ensureVisible(inSheet('Appliquer'));
          await tester.pumpAndSettle();
          expect(tester.getSize(inSheet('Appliquer')).width, lessThan(320));
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('lignes de la feuille (règle pure)', () {
    final draft = PosterParser.parse(_sportPoster, DateTime.now());

    test('rien de saisi : tout ce qui est lu est coché', () {
      final rows = posterReviewRows(draft, const PosterFormState());
      expect(rows.where((r) => r.initiallyChecked).map((r) => r.field),
          [PosterField.title, PosterField.start, PosterField.place, PosterField.price, PosterField.description]);
    });

    test('début / fin choisis par l\'utilisateur : décochés, « remplacerait »', () {
      final rows = posterReviewRows(draft, const PosterFormState(startTouched: true));
      final start = rows.firstWhere((r) => r.field == PosterField.start);
      expect(start.wouldReplace, isTrue);
      expect(start.initiallyChecked, isFalse);
    });

    test('prix « 12,50 TND »', () {
      expect(posterPriceLabel(const PosterDraft(priceTnd: 12.5)), '12,50 TND');
      expect(posterPriceLabel(const PosterDraft(priceTnd: 5)), '5 TND');
      expect(posterPriceLabel(const PosterDraft(isFree: true)), 'Gratuit');
    });
  });
}
