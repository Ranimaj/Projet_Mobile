import 'package:campusconnect/core/utils/geo.dart';
import 'package:campusconnect/models/article_model.dart';
import 'package:campusconnect/screens/vente_don/article_detail_screen.dart';
import 'package:campusconnect/screens/vente_don/article_form_screen.dart';
import 'package:campusconnect/screens/vente_don/favorites_screen.dart';
import 'package:campusconnect/screens/vente_don/my_articles_screen.dart';
import 'package:campusconnect/screens/vente_don/vente_don_list_screen.dart';
import 'package:campusconnect/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../helpers/articles.dart';
import '../helpers/authenticated.dart';
import '../helpers/market.dart';

const _campus = GeoPoint2(36.8992, 10.1897);

void main() {
  late AuthHarness h;
  late FakeArticleRepo repo;

  setUpAll(() => initializeDateFormatting('fr_FR'));

  setUp(() {
    h = AuthHarness();
    repo = FakeArticleRepo([
      article('book',
          title: 'Livre de Java',
          category: 'Livres',
          price: 15,
          createdAt: DateTime(2026, 11, 1),
          latitude: _campus.latitude,
          longitude: _campus.longitude),
      article('gift', title: 'Manteau chaud', category: 'Vêtements', price: null, createdAt: DateTime(2026, 11, 3)),
      article('desk', title: 'Bureau en bois', category: 'Mobilier', price: 80, createdAt: DateTime(2026, 11, 2)),
      article('sold', title: 'Vélo vendu', status: ArticleStatus.done, createdAt: DateTime(2026, 11, 4)),
    ]);
  });
  tearDown(() => h.dispose());

  Finder card(String id) => find.byKey(ValueKey('article-$id'));

  testWidgets('shows the available articles with their price and hides finished ones', (tester) async {
    await h.signIn(tester);
    await pumpMarket(tester, h, marketProvider(repo), const VenteDonListScreen());
    expect(find.text('Livre de Java'), findsOneWidget);
    expect(find.text('15 DT'), findsOneWidget);
    expect(find.text('Manteau chaud'), findsOneWidget);
    expect(find.text('Gratuit'), findsWidgets);
    expect(find.text('Vélo vendu'), findsNothing);
    expect(find.text('3 articles'), findsOneWidget);
    expect(find.byKey(const Key('publish-article')), findsOneWidget);
  });

  testWidgets('typing in the search narrows the grid, accents ignored', (tester) async {
    await h.signIn(tester);
    await pumpMarket(tester, h, marketProvider(repo), const VenteDonListScreen());
    await tester.enterText(find.byKey(const Key('article-search')), 'MANTEAU');
    await tester.pump();
    expect(card('gift'), findsOneWidget);
    expect(card('book'), findsNothing);
    expect(find.text('1 article'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('article-search')), 'velo');
    await tester.pump();
    expect(find.text('Aucun résultat'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reset-all')));
    await tester.pump();
    expect(find.text('3 articles'), findsOneWidget);
  });

  testWidgets('category and Gratuit chips filter the grid', (tester) async {
    await h.signIn(tester);
    await pumpMarket(tester, h, marketProvider(repo), const VenteDonListScreen());
    await tester.tap(find.descendant(of: find.byKey(const Key('category-chips')), matching: find.text('Gratuit')));
    await tester.pump();
    expect(card('gift'), findsOneWidget);
    expect(card('desk'), findsNothing);

    await tester.tap(find.descendant(of: find.byKey(const Key('category-chips')), matching: find.text('Tous')));
    await tester.pump();
    await tester.tap(find.descendant(of: find.byKey(const Key('category-chips')), matching: find.text('Livres')));
    await tester.pump();
    expect(card('book'), findsOneWidget);
    expect(card('desk'), findsNothing);
    expect(card('gift'), findsNothing);
  });

  testWidgets('the filter sheet sorts by price', (tester) async {
    await h.signIn(tester);
    final provider = marketProvider(repo);
    await pumpMarket(tester, h, provider, const VenteDonListScreen());
    await tester.tap(find.byKey(const Key('open-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sort-priceDesc')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('apply-filters')));
    await tester.tap(find.byKey(const Key('apply-filters')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Prix décroissant'), findsOneWidget);
    expect([for (final a in provider.items) a.id], ['desk', 'book', 'gift']);
  });

  testWidgets('the filter sheet asks for the position, then filters by distance', (tester) async {
    await h.signIn(tester);
    final provider = marketProvider(repo, locate: () async => const LocationResult.found(_campus));
    await pumpMarket(tester, h, provider, const VenteDonListScreen());
    await tester.tap(find.byKey(const Key('open-filters')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('locate')));
    await tester.tap(find.byKey(const Key('locate')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('distance-1')));
    await tester.tap(find.byKey(const ValueKey('distance-1')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('apply-filters')));
    await tester.tap(find.byKey(const Key('apply-filters')));
    await tester.pumpAndSettle();
    expect(card('book'), findsOneWidget);
    expect(card('desk'), findsNothing);
    expect(find.textContaining('≤ 1 km'), findsOneWidget);
    // La carte affiche la distance.
    expect(find.textContaining('10 m'), findsOneWidget);
  });

  testWidgets('the heart adds the article to the favorites', (tester) async {
    await h.signIn(tester);
    final provider = marketProvider(repo);
    await pumpMarket(tester, h, provider, const VenteDonListScreen());
    await tester.tap(find.descendant(of: card('book'), matching: find.byTooltip('Ajouter aux favoris')));
    await tester.pump();
    expect(provider.byId('book')!.favoritedBy, ['uid-1']);
    expect(find.descendant(of: card('book'), matching: find.byTooltip('Retirer des favoris')), findsOneWidget);
  });

  testWidgets('header buttons open favorites, my articles and the form', (tester) async {
    await h.signIn(tester);
    await pumpMarket(tester, h, marketProvider(repo), const VenteDonListScreen());
    await tester.tap(find.byKey(const Key('open-favorites')));
    await tester.pumpAndSettle();
    expect(find.byType(FavoritesScreen), findsOneWidget);
    expect(find.text('Aucun favori'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('open-my-articles')));
    await tester.pumpAndSettle();
    expect(find.byType(MyArticlesScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('publish-article')));
    await tester.pumpAndSettle();
    expect(find.byType(ArticleFormScreen), findsOneWidget);
  });

  testWidgets('tapping a card opens its detail', (tester) async {
    await h.signIn(tester);
    await pumpMarket(tester, h, marketProvider(repo), const VenteDonListScreen());
    await tester.tap(find.text('Bureau en bois'));
    await tester.pumpAndSettle();
    expect(find.byType(ArticleDetailScreen), findsOneWidget);
    expect(find.text('80 DT'), findsWidgets);
  });

  testWidgets('a visitor can browse but not publish, like or message', (tester) async {
    await pumpMarket(tester, h, marketProvider(repo), const VenteDonListScreen());
    expect(find.text('Livre de Java'), findsOneWidget);
    expect(find.byKey(const Key('publish-article')), findsNothing);
    expect(find.byKey(const Key('open-messages')), findsNothing);
    expect(find.byTooltip('Ajouter aux favoris'), findsNothing);
  });

  testWidgets('an article published offline shows its local photo and a waiting note', (tester) async {
    await h.signIn(tester);
    final photos = FakePhotoStore()..files.add('/local/photo-9.jpg');
    repo = FakeArticleRepo([
      article('offline', title: 'Lampe hors ligne', imageUrls: const ['/local/photo-9.jpg']),
    ]);
    await pumpMarket(tester, h, marketProvider(repo, online: false, photos: photos), const VenteDonListScreen());
    expect(find.text('Lampe hors ligne'), findsOneWidget);
    expect(find.textContaining('En attente de réseau'), findsOneWidget);
  });

  testWidgets('empty market shows the empty state', (tester) async {
    await h.signIn(tester);
    await pumpMarket(tester, h, marketProvider(FakeArticleRepo()), const VenteDonListScreen());
    expect(find.text('Aucun article pour le moment'), findsOneWidget);
  });
}
