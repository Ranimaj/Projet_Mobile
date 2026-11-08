import 'dart:convert';
import 'dart:io';

import 'package:campusconnect/core/theme/app_theme.dart';
import 'package:campusconnect/screens/evenements/add_event_screen.dart';
import 'package:campusconnect/screens/evenements/category_classifier.dart';
import 'package:campusconnect/screens/evenements/event_categories.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR')); // boutons Début / Fin
  final classifier = CategoryClassifier.fromJson(
      jsonDecode(File('assets/ml/category_model.json').readAsStringSync()) as Map<String, dynamic>);

  final chip = find.textContaining('Suggestion');
  final titleField = find.widgetWithText(TextFormField, "Titre de l'événement");
  final descField = find.widgetWithText(TextFormField, 'Description');
  final categoryField = find.byType(DropdownButtonFormField<String>);

  String? selectedCategory(WidgetTester tester) =>
      tester.state<FormFieldState<String>>(categoryField).value;

  /// Création d'un événement (catégorie par défaut : Conférence), modèle réel
  /// chargé de façon synchrone. Écran étroit et grand texte par défaut.
  Future<void> pump(WidgetTester tester, {double width = 320, double textScale = 1.5}) async {
    tester.view.physicalSize = Size(width, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: AddEventScreen(loadClassifier: () => SynchronousFuture(classifier)),
    ));
    await tester.pump();
  }

  Future<void> type(WidgetTester tester, String title, String description) async {
    await tester.enterText(titleField, title);
    await tester.enterText(descField, description);
  }

  testWidgets('la puce apparaît après 600 ms, sans changer la catégorie', (tester) async {
    await pump(tester);
    expect(selectedCategory(tester), EventCategories.conference);

    await type(tester, 'Tournoi de football', 'Match inter-classes au stade du campus');
    await tester.pump(const Duration(milliseconds: 500));
    expect(chip, findsNothing, reason: 'pas avant la fin du délai de 600 ms');

    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Suggestion : Sport (98 %)'), findsOneWidget);
    expect(find.text('Appliquer'), findsOneWidget);
    expect(selectedCategory(tester), EventCategories.conference, reason: 'jamais appliquée seule');
    expect(tester.takeException(), isNull); // aucun débordement à 320 px, texte ×1,5
  });

  testWidgets('texte ×2 à 320 px : puce lisible, aucun débordement', (tester) async {
    await pump(tester, textScale: 2.0);
    await type(tester, 'Tournoi de football', 'Match inter-classes au stade du campus');
    await tester.pump(const Duration(milliseconds: 600));
    expect(chip, findsOneWidget);
    await tester.ensureVisible(find.text('Appliquer'));
    expect(tester.getSize(find.text('Appliquer')).width, lessThan(320));
    expect(tester.takeException(), isNull);
  });

  testWidgets('« Appliquer » choisit la catégorie et masque la puce', (tester) async {
    await pump(tester);
    await type(tester, 'Tournoi de football', 'Match inter-classes au stade du campus');
    await tester.pump(const Duration(milliseconds: 600));

    await tester.ensureVisible(find.text('Appliquer'));
    await tester.tap(find.text('Appliquer'));
    await tester.pump();

    expect(selectedCategory(tester), EventCategories.sport);
    expect(find.descendant(of: categoryField, matching: find.text('Sport')), findsOneWidget);
    expect(chip, findsNothing);
  });

  testWidgets('« Ignorer » masque la puce pour ce texte', (tester) async {
    await pump(tester);
    await type(tester, 'Tournoi de football', 'Match inter-classes au stade du campus');
    await tester.pump(const Duration(milliseconds: 600));

    await tester.ensureVisible(find.text('Ignorer'));
    await tester.tap(find.text('Ignorer'));
    await tester.pump();
    expect(chip, findsNothing);
    expect(selectedCategory(tester), EventCategories.conference);

    // Le texte change mais suggère toujours Sport : pas de nouvelle insistance.
    await tester.enterText(descField, 'Match inter-classes au stade du campus, venez nombreux');
    await tester.pump(const Duration(milliseconds: 600));
    expect(chip, findsNothing);
  });

  testWidgets('puce masquée quand la catégorie choisie est déjà la suggestion', (tester) async {
    await pump(tester);
    await type(tester, "Conférence sur l'intelligence artificielle", 'Un chercheur présente ses travaux');
    await tester.pump(const Duration(milliseconds: 600));
    expect(selectedCategory(tester), EventCategories.conference);
    expect(chip, findsNothing);
  });

  testWidgets('puce masquée pour du charabia', (tester) async {
    await pump(tester);
    await type(tester, 'Zzzz qqqq wwww', 'xxxx yyyy kkkk');
    await tester.pump(const Duration(milliseconds: 600));
    expect(chip, findsNothing);
  });

  testWidgets('moins de 15 caractères : rien, et la puce disparaît si on efface', (tester) async {
    await pump(tester);
    await type(tester, 'Foot', 'Stade');
    await tester.pump(const Duration(milliseconds: 600));
    expect(chip, findsNothing);

    await type(tester, 'Tournoi de football', 'Match inter-classes au stade du campus');
    await tester.pump(const Duration(milliseconds: 600));
    expect(chip, findsOneWidget);

    await type(tester, 'Foot', '');
    await tester.pump();
    expect(chip, findsNothing);
  });

  testWidgets('modèle indisponible : aucun crash, aucune puce', (tester) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: AddEventScreen(loadClassifier: () => SynchronousFuture<CategoryClassifier?>(null)),
    ));
    await type(tester, 'Tournoi de football', 'Match inter-classes au stade du campus');
    await tester.pump(const Duration(milliseconds: 600));
    expect(chip, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
