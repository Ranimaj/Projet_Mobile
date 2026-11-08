import 'dart:io';

import 'package:campusconnect/core/utils/geo.dart';
import 'package:campusconnect/providers/article_provider.dart';
import 'package:campusconnect/screens/vente_don/article_form_screen.dart';
import 'package:campusconnect/services/ai/article_ai.dart';
import 'package:campusconnect/services/ai/category_mapper.dart';
import 'package:campusconnect/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/articles.dart';
import '../helpers/authenticated.dart';
import '../helpers/market.dart';

void main() {
  late AuthHarness h;
  late FakeArticleRepo repo;

  setUp(() {
    h = AuthHarness();
    repo = FakeArticleRepo();
  });
  tearDown(() => h.dispose());

  // Écran haut : la carte « Assistant IA » allonge le formulaire et les
  // champs du bas doivent être construits.
  Future<void> pumpForm(WidgetTester tester, AuthHarness h, ArticleProvider p, Widget screen) =>
      pumpMarket(tester, h, p, screen, size: const Size(420, 1900));

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('submit-article')));
    await tester.pumpAndSettle();
  }

  group('ArticleFormValidators', () {
    test('title', () {
      expect(ArticleFormValidators.title(''), 'Titre requis');
      expect(ArticleFormValidators.title('ab'), isNotNull);
      expect(ArticleFormValidators.title('x' * 81), isNotNull);
      expect(ArticleFormValidators.title('Lampe'), isNull);
    });

    test('description', () {
      expect(ArticleFormValidators.description(' '), 'Description requise');
      expect(ArticleFormValidators.description('trop court'), isNull); // 10 caractères
      expect(ArticleFormValidators.description('court'), isNotNull);
    });

    test('price accepts a comma and is ignored for a gift', () {
      expect(ArticleFormValidators.price('12,5', isFree: false), isNull);
      expect(ArticleFormValidators.parsePrice('12,5'), 12.5);
      expect(ArticleFormValidators.price('abc', isFree: false), 'Prix invalide');
      expect(ArticleFormValidators.price('0', isFree: false), isNotNull);
      expect(ArticleFormValidators.price('', isFree: true), isNull);
    });
  });

  testWidgets('empty form shows the errors and saves nothing', (tester) async {
    await h.signIn(tester);
    await pumpForm(tester, h, marketProvider(repo), const ArticleFormScreen());
    await submit(tester);
    expect(find.text('Titre requis'), findsOneWidget);
    expect(find.text('Description requise'), findsOneWidget);
    expect(find.text('Prix invalide'), findsOneWidget);
    expect(repo.creates, isEmpty);
  });

  testWidgets('publishes a sale with category, price and position', (tester) async {
    await h.signIn(tester);
    final provider = marketProvider(repo,
        locate: () async => const LocationResult.found(GeoPoint2(36.9, 10.19)));
    await pumpForm(tester, h, provider, const ArticleFormScreen());
    await tester.enterText(find.byKey(const Key('field-title')), 'Livre de Java');
    await tester.enterText(find.byKey(const Key('field-description')), 'Deuxième édition, quelques notes.');
    await tester.tap(find.byKey(const ValueKey('category-Livres')));
    await tester.enterText(find.byKey(const Key('field-price')), '12,5');
    await tester.scrollUntilVisible(find.byKey(const Key('add-location')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-location')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('location-set')), findsOneWidget);
    await submit(tester);

    final (item, online) = repo.creates.single;
    expect(online, isTrue);
    expect(item.title, 'Livre de Java');
    expect(item.category, 'Livres');
    expect(item.price, 12.5);
    expect(item.ownerId, 'uid-1');
    expect(item.ownerName, 'Amel Ben Salah');
    expect(item.latitude, 36.9);
    expect(find.text('Article publié !'), findsOneWidget);
    expect(find.byType(ArticleFormScreen), findsNothing);
  });

  testWidgets('when the GPS gives nothing, "Campus" sets the campus position', (tester) async {
    await h.signIn(tester);
    final provider = marketProvider(repo,
        locate: () async => const LocationResult.failed(LocationFailure.unavailable));
    await pumpForm(tester, h, provider, const ArticleFormScreen());
    await tester.enterText(find.byKey(const Key('field-title')), 'Lampe de bureau');
    await tester.enterText(find.byKey(const Key('field-description')), 'Lampe LED, fonctionne bien.');
    await tester.tap(find.byKey(const ValueKey('category-Mobilier')));
    await tester.enterText(find.byKey(const Key('field-price')), '20');
    await tester.scrollUntilVisible(find.byKey(const Key('add-location')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-location')));
    await tester.pumpAndSettle();
    expect(find.text('Position introuvable pour le moment.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('use-campus-position')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('location-set')), findsOneWidget);
    await submit(tester);
    expect(repo.creates.single.$1.latitude, kCampusPosition.latitude);
    expect(repo.creates.single.$1.longitude, kCampusPosition.longitude);
  });

  testWidgets('a gift hides the price and is saved without one', (tester) async {
    await h.signIn(tester);
    await pumpForm(tester, h, marketProvider(repo), const ArticleFormScreen());
    await tester.enterText(find.byKey(const Key('field-title')), 'Manteau');
    await tester.enterText(find.byKey(const Key('field-description')), 'Taille M, très chaud.');
    await tester.tap(find.byKey(const Key('field-free')));
    await tester.pump();
    expect(find.byKey(const Key('field-price')), findsNothing);
    await submit(tester);
    expect(repo.creates.single.$1.price, isNull);
    expect(repo.creates.single.$1.isFree, isTrue);
  });

  testWidgets('editing pre-fills the form and saves a patch', (tester) async {
    await h.signIn(tester);
    final original = article('a1',
        ownerId: 'uid-1', title: 'Bureau', description: 'Bureau en pin massif.', price: 60, category: 'Mobilier');
    repo = FakeArticleRepo([original]);
    await pumpForm(tester, h, marketProvider(repo), ArticleFormScreen(article: original));
    expect(find.text('Modifier l\'article'), findsOneWidget);
    expect(find.text('Bureau'), findsOneWidget);
    expect(find.text('60'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('field-title')), 'Bureau d\'étudiant');
    await tester.enterText(find.byKey(const Key('field-price')), '45');
    await submit(tester);

    final (id, patch, _) = repo.updates.single;
    expect(id, 'a1');
    expect(patch['title'], 'Bureau d\'étudiant');
    expect(patch['price'], 45);
    expect(patch['category'], 'Mobilier');
    expect(find.text('Article modifié !'), findsOneWidget);
  });

  testWidgets('without network, a new article and its photo are saved on the phone', (tester) async {
    await h.signIn(tester);
    final photos = FakePhotoStore();
    final provider = marketProvider(repo, online: false, photos: photos);
    await pumpForm(tester, h, provider,
        ArticleFormScreen(pickImages: () async => [File('/galerie/livre.jpg')]));
    await tester.tap(find.byKey(const Key('add-photos')));
    await tester.pump();
    expect(find.text('Photos (1/6)'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('field-title')), 'Livre');
    await tester.enterText(find.byKey(const Key('field-description')), 'Livre de cours complet.');
    await tester.enterText(find.byKey(const Key('field-price')), '20');
    await submit(tester);
    expect(repo.creates.single.$1.imageUrls, ['/local/photo-0.jpg']);
    expect(find.text('Article publié !'), findsOneWidget);
  });

  testWidgets('without network, a new article without photo is saved too', (tester) async {
    await h.signIn(tester);
    await pumpForm(tester, h, marketProvider(repo, online: false), const ArticleFormScreen());
    expect(find.textContaining('Hors ligne'), findsNothing);
    await tester.enterText(find.byKey(const Key('field-title')), 'Chaise');
    await tester.enterText(find.byKey(const Key('field-description')), 'Chaise pliante noire.');
    await tester.enterText(find.byKey(const Key('field-price')), '5');
    await submit(tester);
    expect(repo.creates.single.$1.title, 'Chaise');
  });

  group('Assistant IA', () {
    testWidgets('the photo picks the category, keywords fill the title, labels are saved', (tester) async {
      await h.signIn(tester);
      final ai = ArticleAi(
        tagger: FakeTagger(const [ImageTag('Book', 0.93), ImageTag('Paper', 0.7)]),
        writer: FakeWriter(),
      );
      await pumpForm(tester, h, marketProvider(repo),
          ArticleFormScreen(ai: ai, pickImages: () async => [File('/galerie/livre.jpg')]));
      await tester.tap(find.byKey(const Key('add-photos')));
      await tester.pumpAndSettle();
      expect(find.text('Catégorie reconnue : Livres (93 %)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ai-keyword-livre')));
      await tester.pump();
      expect(find.text('Livre'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('field-description')), 'Livre de cours complet.');
      await tester.enterText(find.byKey(const Key('field-price')), '15');
      await submit(tester);
      final item = repo.creates.single.$1;
      expect(item.category, 'Livres');
      expect(item.labels, ['book', 'paper']);
    });

    testWidgets('a manual category choice is not overridden by the photo', (tester) async {
      await h.signIn(tester);
      final ai = ArticleAi(tagger: FakeTagger(const [ImageTag('Book', 0.93)]), writer: FakeWriter());
      await pumpForm(tester, h, marketProvider(repo),
          ArticleFormScreen(ai: ai, pickImages: () async => [File('/g/x.jpg')]));
      await tester.ensureVisible(find.byKey(const ValueKey('category-Mobilier')));
      await tester.tap(find.byKey(const ValueKey('category-Mobilier')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('add-photos')));
      await tester.tap(find.byKey(const Key('add-photos')));
      await tester.pumpAndSettle();
      expect(find.textContaining('La photo ressemble à : Livres'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('ai-apply-category')));
      await tester.tap(find.byKey(const Key('ai-apply-category')));
      await tester.pump();
      expect(find.textContaining('Catégorie reconnue : Livres'), findsOneWidget);
    });

    testWidgets('an unknown object asks the user to choose', (tester) async {
      await h.signIn(tester);
      final ai = ArticleAi(tagger: FakeTagger(const [], fail: true), writer: FakeWriter());
      await pumpForm(tester, h, marketProvider(repo),
          ArticleFormScreen(ai: ai, pickImages: () async => [File('/g/x.jpg')]));
      await tester.tap(find.byKey(const Key('add-photos')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Objet non reconnu'), findsOneWidget);
    });

    testWidgets('price advice from similar articles fills the price', (tester) async {
      await h.signIn(tester);
      repo = FakeArticleRepo([
        article('1', title: 'Calculatrice Casio', category: 'Électronique', price: 30),
        article('2', title: 'Calculatrice graphique', category: 'Électronique', price: 50),
      ]);
      final ai = ArticleAi(tagger: FakeTagger(const []), writer: FakeWriter());
      await pumpForm(tester, h, marketProvider(repo), ArticleFormScreen(ai: ai));
      await tester.ensureVisible(find.byKey(const ValueKey('category-Électronique')));
      await tester.tap(find.byKey(const ValueKey('category-Électronique')));
      await tester.enterText(find.byKey(const Key('field-title')), 'Calculatrice TI-83');
      await tester.pump();
      expect(find.textContaining('Prix conseillé : 35 à 45 DT'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('ai-use-price')));
      await tester.tap(find.byKey(const Key('ai-use-price')));
      await tester.pump();
      expect(find.text('40'), findsOneWidget);
    });

    testWidgets('Gemini writes the description', (tester) async {
      await h.signIn(tester);
      final writer = FakeWriter('Calculatrice en parfait état, remise sur le campus.');
      final ai = ArticleAi(tagger: FakeTagger(const []), writer: writer);
      await pumpForm(tester, h, marketProvider(repo), ArticleFormScreen(ai: ai));
      await tester.enterText(find.byKey(const Key('field-title')), 'Calculatrice');
      await tester.ensureVisible(find.byKey(const Key('ai-write')));
      await tester.tap(find.byKey(const Key('ai-write')));
      await tester.pumpAndSettle();
      expect(find.text('Calculatrice en parfait état, remise sur le campus.'), findsOneWidget);
      expect(writer.last!.title, 'Calculatrice');
    });

    testWidgets('moderation blocks forbidden items and warns about contact details', (tester) async {
      await h.signIn(tester);
      final ai = ArticleAi(tagger: FakeTagger(const []), writer: FakeWriter());
      await pumpForm(tester, h, marketProvider(repo), ArticleFormScreen(ai: ai));
      await tester.enterText(find.byKey(const Key('field-title')), 'Vends médicaments');
      await tester.enterText(find.byKey(const Key('field-description')), 'Boîte entière, jamais ouverte.');
      await tester.enterText(find.byKey(const Key('field-price')), '5');
      await submit(tester);
      expect(find.byKey(const Key('moderation-blocked')), findsOneWidget);
      await tester.tap(find.text('Modifier'));
      await tester.pumpAndSettle();
      expect(repo.creates, isEmpty);

      await tester.enterText(find.byKey(const Key('field-title')), 'Lampe de bureau');
      await tester.enterText(find.byKey(const Key('field-description')), 'Appelle-moi au 22 123 456.');
      await submit(tester);
      expect(find.byKey(const Key('moderation-warning')), findsOneWidget);
      await tester.tap(find.byKey(const Key('publish-anyway')));
      await tester.pumpAndSettle();
      expect(repo.creates.single.$1.title, 'Lampe de bureau');
    });
  });
}
