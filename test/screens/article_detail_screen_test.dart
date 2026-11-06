import 'package:campusconnect/models/article_model.dart';
import 'package:campusconnect/screens/vente_don/article_detail_screen.dart';
import 'package:campusconnect/screens/vente_don/article_form_screen.dart';
import 'package:campusconnect/screens/vente_don/chat_screen.dart';
import 'package:campusconnect/services/chat_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../helpers/articles.dart';
import '../helpers/authenticated.dart';
import '../helpers/market.dart';

void main() {
  late AuthHarness h;
  late FakeArticleRepo repo;
  final bike = article('bike',
      ownerId: 'seller-1',
      ownerName: 'Sami Trabelsi',
      title: 'Vélo de ville',
      description: 'Vélo en très bon état, avec antivol.',
      price: 150,
      category: 'Autre',
      viewCount: 4);
  final mine = article('mine', ownerId: 'uid-1', ownerName: 'Amel Ben Salah', title: 'Ma lampe', price: null);

  setUpAll(() => initializeDateFormatting('fr_FR'));

  setUp(() {
    h = AuthHarness();
    repo = FakeArticleRepo([bike, mine]);
  });
  tearDown(() => h.dispose());

  testWidgets('a buyer sees the article, its seller and the views (counted once)', (tester) async {
    await h.signIn(tester);
    final provider = marketProvider(repo);
    await pumpMarket(tester, h, provider, ArticleDetailScreen(article: bike));
    expect(find.byKey(const Key('article-title')), findsOneWidget);
    expect(find.text('150 DT'), findsOneWidget);
    expect(find.text('Sami Trabelsi'), findsOneWidget);
    expect(find.text('5 vues'), findsOneWidget);
    expect(find.byKey(const Key('contact-seller')), findsOneWidget);
    expect(find.text('Contacter Sami'), findsOneWidget);
    expect(find.byKey(const Key('owner-menu')), findsNothing);
    expect(repo.updates.single.$2, {'viewCount': 5});
  });

  testWidgets('the heart toggles the favorite', (tester) async {
    await h.signIn(tester);
    final provider = marketProvider(repo);
    await pumpMarket(tester, h, provider, ArticleDetailScreen(article: bike));
    await tester.tap(find.byKey(const Key('toggle-favorite')));
    await tester.pump();
    expect(provider.byId('bike')!.favoritedBy, ['uid-1']);
    expect(find.byTooltip('Retirer des favoris'), findsOneWidget);
    expect(find.text('1 favori'), findsOneWidget);
  });

  testWidgets('contacting the seller opens a real conversation', (tester) async {
    await h.signIn(tester);
    final db = FakeFirebaseFirestore();
    final chat = ChatService(firestore: db);
    await pumpMarket(tester, h, marketProvider(repo), ArticleDetailScreen(article: bike, chatService: chat));
    await tester.tap(find.byKey(const Key('contact-seller')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);

    await tester.enterText(find.byKey(const Key('message-input')), 'Il est toujours dispo ?');
    await tester.tap(find.byKey(const Key('send-message')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.text('Il est toujours dispo ?'), findsOneWidget);

    final header = await db.collection('conversations').doc('bike_uid-1').get();
    expect(header.data()!['participants'], containsAll(['uid-1', 'seller-1']));
    expect(header.data()!['unreadBy'], ['seller-1']);
  });

  testWidgets('the owner manages the article from the menu', (tester) async {
    await h.signIn(tester);
    final provider = marketProvider(repo);
    await pumpMarket(tester, h, provider, ArticleDetailScreen(article: mine));
    expect(find.byKey(const Key('contact-seller')), findsNothing);
    expect(find.byKey(const Key('toggle-favorite')), findsNothing);
    expect(find.byKey(const Key('edit-article')), findsOneWidget);
    // Le propriétaire ne compte pas de vue.
    expect(repo.updates, isEmpty);

    await tester.tap(find.byKey(const Key('owner-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('action-reserve')));
    await tester.pumpAndSettle();
    expect(provider.byId('mine')!.status, ArticleStatus.reserved);
    expect(find.text('Réservé'), findsOneWidget);

    await tester.tap(find.byKey(const Key('owner-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('action-available')), findsOneWidget);
    expect(find.text('Marquer comme donné'), findsOneWidget);
    await tester.tap(find.byKey(const Key('action-edit')));
    await tester.pumpAndSettle();
    expect(find.byType(ArticleFormScreen), findsOneWidget);
  });

  testWidgets('the owner can delete after confirming', (tester) async {
    await h.signIn(tester);
    final provider = marketProvider(repo);
    await pumpMarket(tester, h, provider, ArticleDetailScreen(article: mine));
    await tester.tap(find.byKey(const Key('owner-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('action-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-delete')));
    await tester.pumpAndSettle();
    expect(provider.byId('mine'), isNull);
    expect(find.byType(ArticleDetailScreen), findsNothing);
    expect(find.text('Article supprimé.'), findsOneWidget);
  });

  testWidgets('a visitor is asked to sign in to contact the seller', (tester) async {
    await pumpMarket(tester, h, marketProvider(repo), ArticleDetailScreen(article: bike));
    expect(find.text('Connecte-toi pour contacter le vendeur.'), findsOneWidget);
    expect(find.byKey(const Key('toggle-favorite')), findsNothing);
    expect(repo.updates, isEmpty);
  });

  testWidgets('offline, the contact button is disabled', (tester) async {
    await h.signIn(tester);
    await pumpMarket(tester, h, marketProvider(repo, online: false), ArticleDetailScreen(article: bike));
    expect(find.textContaining('Hors ligne'), findsOneWidget);
  });
}
