import 'dart:io';

import 'package:campusconnect/core/utils/geo.dart';
import 'package:campusconnect/screens/vente_don/article_form_screen.dart';
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
    await pumpMarket(tester, h, marketProvider(repo), const ArticleFormScreen());
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
    await pumpMarket(tester, h, provider, const ArticleFormScreen());
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

  testWidgets('a gift hides the price and is saved without one', (tester) async {
    await h.signIn(tester);
    await pumpMarket(tester, h, marketProvider(repo), const ArticleFormScreen());
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
    await pumpMarket(tester, h, marketProvider(repo), ArticleFormScreen(article: original));
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

  testWidgets('offline, a new article and its photo stay on the phone', (tester) async {
    await h.signIn(tester);
    final photos = FakePhotoStore();
    final provider = marketProvider(repo, online: false, photos: photos);
    await pumpMarket(tester, h, provider,
        ArticleFormScreen(pickImages: () async => [File('/galerie/livre.jpg')]));
    await tester.tap(find.byKey(const Key('add-photos')));
    await tester.pump();
    expect(find.text('Photos (1/6)'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('field-title')), 'Livre');
    await tester.enterText(find.byKey(const Key('field-description')), 'Livre de cours complet.');
    await tester.enterText(find.byKey(const Key('field-price')), '20');
    await submit(tester);
    final (item, online) = repo.creates.single;
    expect(online, isFalse);
    expect(item.imageUrls, ['/local/photo-0.jpg']);
    expect(find.text('Article publié ! Il sera envoyé au retour du réseau.'), findsOneWidget);
  });

  testWidgets('offline, a new article is queued (no photo)', (tester) async {
    await h.signIn(tester);
    await pumpMarket(tester, h, marketProvider(repo, online: false), const ArticleFormScreen());
    expect(find.textContaining('Hors ligne'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('field-title')), 'Chaise');
    await tester.enterText(find.byKey(const Key('field-description')), 'Chaise pliante noire.');
    await tester.enterText(find.byKey(const Key('field-price')), '5');
    await submit(tester);
    expect(repo.creates.single.$2, isFalse);
  });
}
