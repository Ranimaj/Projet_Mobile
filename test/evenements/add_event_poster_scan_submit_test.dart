import 'dart:io';

import 'package:campusconnect/core/constants/app_constants.dart';
import 'package:campusconnect/core/theme/app_tokens.dart';
import 'package:campusconnect/models/event_model.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/providers/connectivity_provider.dart';
import 'package:campusconnect/providers/event_provider.dart';
import 'package:campusconnect/screens/evenements/add_event_screen.dart';
import 'package:campusconnect/screens/evenements/category_classifier.dart';
import 'package:campusconnect/screens/evenements/event_actor.dart';
import 'package:campusconnect/screens/evenements/poster_ocr.dart';
import 'package:campusconnect/screens/evenements/poster_parser.dart';
import 'package:campusconnect/screens/evenements/poster_scan_sheets.dart';
import 'package:campusconnect/services/local_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import '../helpers/authenticated.dart';
import '../helpers/local_db.dart';
import 'poster_fixtures.dart';

/// Faux lecteur : renvoie des lignes fixées, sans ML Kit.
class _FakeReader implements PosterTextReader {
  final PosterOcrResult result;
  _FakeReader(this.result);
  @override
  Future<PosterOcrResult> read(File image) async => result;
}

/// Le scanner ne fait que préremplir : à l'enregistrement, le parcours normal
/// s'applique (validateurs du formulaire, puis EventProvider avec la personne
/// connectée, l'organisateur, l'id réutilisé et le contrôle du contenu).
void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  final day = DateTime.now().add(const Duration(days: 30));
  final dayText = '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}/${day.year}';
  PosterOcrLine l(String text, double top, double height) => PosterOcrLine(text, top: top, height: height);
  final poster = PosterOcrResult([
    l('ESPRIT · VIE DE CAMPUS', 40, 14),
    l('TOURNOI DE FOOTBALL INTER-CLASSES', 120, 64),
    l('$dayText à 14h30', 260, 30),
    l("Lieu : Stade de l'ESPRIT, Ghazala", 310, 26),
    l('Équipes de 7 joueurs · Entrée libre', 360, 24),
    l('Club Sport ESPRIT', 760, 14),
  ]);

  late AuthHarness auth;
  late LocalStore store;

  setUp(() async {
    await openTestDatabase();
    store = LocalStore();
    auth = AuthHarness();
  });

  tearDown(() async {
    await auth.dispose();
    await closeTestDatabase();
  });

  /// Ouvre le formulaire (poussé sur une page, pour que l'enregistrement
  /// puisse le refermer), scanne l'affiche, applique sans garder l'image.
  Future<void> scanAndApply(WidgetTester tester, EventProvider events, {PosterOcrResult? ocr}) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await auth.signIn(tester); // sampleUser : uid-1
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth.provider),
        ChangeNotifierProvider<ConnectivityProvider>.value(value: auth.connectivity),
        ChangeNotifierProvider<EventProvider>.value(value: events),
      ],
      child: MaterialApp(
        // Jetons de l'app sans Google Fonts : l'écriture SQLite réelle (runAsync)
        // laisserait sinon échouer le téléchargement des polices.
        theme: ThemeData(extensions: const [AppTokens.light]),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => AddEventScreen(
                  loadClassifier: () => SynchronousFuture<CategoryClassifier?>(null),
                  posterTextReader: _FakeReader(ocr ?? poster),
                  pickScanImage: (_) async => XFile.fromData(Uint8List.fromList([0xFF, 0xD8, 0xFF]),
                      name: 'affiche.jpg', path: '/tmp/affiche.jpg'),
                ),
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scanner une affiche'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choisir dans la galerie'));
    await tester.pumpAndSettle();
    final keepImage = find.widgetWithText(SwitchListTile, "Utiliser cette image comme affiche de l'événement");
    await tester.ensureVisible(keepImage);
    await tester.tap(keepImage);
    await tester.pump();
    final apply = find.descendant(of: find.byType(PosterReviewSheet), matching: find.text('Appliquer'));
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();
  }

  /// « Créer l'événement » : l'écriture SQLite est réelle, donc hors du temps simulé.
  Future<void> submit(WidgetTester tester) async {
    // Le message « Champs préremplis » du scanner disparaît d'abord (4 s).
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    final create = find.text("Créer l'événement");
    await tester.ensureVisible(create);
    await tester.runAsync(() async {
      await tester.tap(create);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('affiche scannée puis « Créer » : enregistrée par EventProvider pour la personne connectée',
      (tester) async {
    final events = EventProvider(store: store, actor: () => const EventActor('uid-1'));
    await scanAndApply(tester, events);
    await submit(tester);

    final saved = store.all(AppConstants.eventsCollection);
    expect(saved, hasLength(1));
    final e = EventModel.fromMap(saved.single.id, saved.single.data);
    expect(e.organizerId, 'uid-1');
    expect(e.title, 'Tournoi de football inter-classes');
    expect(e.location, "Stade de l'ESPRIT, Ghazala");
    expect(e.startDate, DateTime(day.year, day.month, day.day, 14, 30));
    expect(e.endDate, e.startDate.add(EventModel.defaultDuration));
    expect(e.price, isNull); // entrée libre
    expect(find.textContaining('Événement créé !'), findsOneWidget);
  });

  testWidgets('affiche 4 (aucun texte courant) : description composée, « Créer » sans rien taper', (tester) async {
    // Lignes de l'affiche 4 de référence ; seule la date est avancée (dans
    // 30 jours) pour que le test ne périme pas.
    final fx = posterFixtures[3];
    final lines = [
      for (final line in fx.lines)
        line.text.contains('/') ? PosterOcrLine('$dayText à 19h30', top: line.top, height: line.height, block: line.block) : line,
    ];
    final events = EventProvider(store: store, actor: () => const EventActor('uid-1'));
    await scanAndApply(tester, events, ocr: PosterOcrResult(lines));
    await submit(tester);

    final saved = store.all(AppConstants.eventsCollection);
    expect(saved, hasLength(1));
    final e = EventModel.fromMap(saved.single.id, saved.single.data);
    final start = DateTime(day.year, day.month, day.day, 19, 30);
    expect(e.startDate, start);
    expect(e.price, 5);
    expect(e.description, "Soirée cinéma en plein air · ${PosterParser.formatWhen(start)} · Cour de l'école · 5 TND");
    expect(find.textContaining('Événement créé !'), findsOneWidget);
  });

  testWidgets('les contrôles du provider s\'appliquent aussi à un formulaire scanné', (tester) async {
    // La session vue par le provider n'est pas l'auteur du formulaire.
    final events = EventProvider(store: store, actor: () => const EventActor('quelqu-un-d-autre'));
    await scanAndApply(tester, events);
    await submit(tester);

    expect(store.all(AppConstants.eventsCollection), isEmpty);
    expect(find.textContaining("L'organisateur doit être la personne connectée"), findsOneWidget);
  });
}
