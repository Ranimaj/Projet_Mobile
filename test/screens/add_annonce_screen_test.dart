import 'package:campusconnect/models/annonce_model.dart';
import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/providers/annonce_provider.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/screens/annonces/add_annonce_screen.dart';
import 'package:campusconnect/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../helpers/authenticated.dart';

class _MockAnnonces extends Mock implements AnnonceProvider {}

class _FakeAnnonce extends Fake implements AnnonceModel {}

void main() {
  late AuthHarness h;
  late _MockAnnonces annonces;

  setUpAll(() => registerFallbackValue(_FakeAnnonce()));

  setUp(() {
    h = AuthHarness();
    annonces = _MockAnnonces();
    when(() => annonces.createAnnonce(any())).thenAnswer((_) async => 'a1');
  });
  tearDown(() => h.dispose());

  Future<void> open(WidgetTester tester, AppUser user) async {
    await h.signIn(tester, user: user);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: h.provider),
        ChangeNotifierProvider<AnnonceProvider>.value(value: annonces),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const AddAnnonceScreen()),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('un étudiant ouvre le formulaire sans erreur, sans la catégorie « Officielle »', (tester) async {
    await open(tester, sampleUser);
    expect(tester.takeException(), isNull);
    expect(find.text('Perdu & Trouvé'), findsOneWidget); // valeur de départ
    expect(find.text('Officielle'), findsNothing);

    await tester.tap(find.text('Perdu & Trouvé'));
    await tester.pumpAndSettle();
    expect(find.text('Officielle'), findsNothing); // pas dans la liste non plus
  });

  testWidgets('un étudiant publie dans une catégorie autorisée', (tester) async {
    await open(tester, sampleUser);
    await tester.enterText(find.widgetWithText(TextFormField, 'Titre'), 'Clé USB trouvée');
    await tester.enterText(find.widgetWithText(TextFormField, 'Contenu'), 'En salle E204, à récupérer à l\'accueil.');
    await tester.tap(find.text('Publier'));
    await tester.pumpAndSettle();

    final draft = verify(() => annonces.createAnnonce(captureAny())).captured.single as AnnonceModel;
    expect(draft.category, 'Perdu & Trouvé');
  });

  testWidgets('un admin part sur « Officielle »', (tester) async {
    await open(
      tester,
      AppUser(
        id: 'admin-1',
        fullName: 'Admin Campus',
        email: 'admin@esprit.tn',
        role: UserRole.admin,
        createdAt: DateTime(2024, 9, 1),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Officielle'), findsOneWidget);
  });
}
