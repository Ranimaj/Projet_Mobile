import 'package:campusconnect/models/article_model.dart';
import 'package:campusconnect/screens/vente_don/article_form_screen.dart';
import 'package:campusconnect/screens/vente_don/chat_screen.dart';
import 'package:campusconnect/screens/vente_don/conversations_screen.dart';
import 'package:campusconnect/screens/vente_don/favorites_screen.dart';
import 'package:campusconnect/screens/vente_don/my_articles_screen.dart';
import 'package:campusconnect/screens/vente_don/vente_don_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import '../helpers/articles.dart';
import '../helpers/authenticated.dart';
import '../helpers/chat.dart';
import '../helpers/market.dart';

/// Écrans du guide de vérification qui n'avaient pas de test dédié :
/// Mes favoris, Mes articles, Mes messages + réponse, réinitialiser les
/// filtres, prix négatif.
void main() {
  late AuthHarness h;

  setUpAll(() => initializeDateFormatting('fr_FR'));
  setUp(() => h = AuthHarness());
  tearDown(() => h.dispose());

  test('a negative or zero price is refused', () {
    expect(ArticleFormValidators.price('-5', isFree: false), contains('positif'));
    expect(ArticleFormValidators.price('0', isFree: false), contains('positif'));
    expect(ArticleFormValidators.price('-5', isFree: true), isNull);
  });

  testWidgets('Mes favoris lists the liked articles; removing the heart drops them', (tester) async {
    await h.signIn(tester);
    final repo = FakeArticleRepo([
      article('book', title: 'Livre de Java', favoritedBy: const ['uid-1']),
      article('lamp', title: 'Lampe'),
    ]);
    final provider = marketProvider(repo);
    await pumpMarket(tester, h, provider, const FavoritesScreen());
    expect(find.text('Livre de Java'), findsOneWidget);
    expect(find.text('Lampe'), findsNothing);

    await tester.tap(find.byTooltip('Retirer des favoris'));
    await tester.pumpAndSettle();
    expect(find.text('Aucun favori'), findsOneWidget);
    expect(provider.byId('book')!.favoritedBy, isEmpty);
  });

  testWidgets('Mes articles shows my articles in every state with chips and stats', (tester) async {
    await h.signIn(tester);
    final repo = FakeArticleRepo([
      article('a', title: 'Vélo dispo', ownerId: 'uid-1', viewCount: 4),
      article('r', title: 'Chaise réservée', ownerId: 'uid-1', status: ArticleStatus.reserved, favoritedBy: const ['x']),
      article('d', title: 'Livre vendu', ownerId: 'uid-1', status: ArticleStatus.done),
      article('o', title: 'Pas à moi', ownerId: 'someone'),
    ]);
    await pumpMarket(tester, h, marketProvider(repo), const MyArticlesScreen());
    expect(find.text('Vélo dispo'), findsOneWidget);
    expect(find.text('Chaise réservée'), findsOneWidget);
    expect(find.text('Livre vendu'), findsOneWidget);
    expect(find.text('Pas à moi'), findsNothing);
    expect(find.text('3'), findsWidgets); // Publiés
    expect(find.text('4'), findsWidgets); // Vues

    await tester.ensureVisible(find.text('Réservés'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Réservés'));
    await tester.pumpAndSettle();
    expect(find.text('Chaise réservée'), findsOneWidget);
    expect(find.text('Vélo dispo'), findsNothing);

    await tester.ensureVisible(find.text('Terminés'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terminés'));
    await tester.pumpAndSettle();
    expect(find.text('Livre vendu'), findsOneWidget);
    expect(find.text('Chaise réservée'), findsNothing);
  });

  testWidgets('Mes messages shows the unread dot; the seller opens the chat and replies', (tester) async {
    await h.signIn(tester); // uid-1 = vendeur ici
    final chat = FakeChatService();
    final item = article('calc', title: 'Calculatrice', ownerId: 'uid-1', ownerName: 'Amel Ben Salah');
    final conv = await chat.openConversation(article: item, buyerId: 'bob', buyerName: 'Bob');
    await chat.send(conv, 'bob', 'Toujours dispo ?');

    await pumpMarket(tester, h, marketProvider(FakeArticleRepo([item])), ConversationsScreen(chatService: chat));
    await tester.pumpAndSettle();
    expect(find.text('Calculatrice'), findsOneWidget);
    expect(find.text('Toujours dispo ?'), findsOneWidget);
    expect(find.byKey(const Key('unread-dot')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('conversation-calc_bob')));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    await tester.enterText(find.byKey(const Key('message-input')), 'Oui, ce soir');
    await tester.tap(find.byKey(const Key('send-message')));
    await tester.pumpAndSettle();
    expect(find.text('Oui, ce soir'), findsOneWidget);
    expect(chat.messages['calc_bob']!.map((m) => m.text), ['Toujours dispo ?', 'Oui, ce soir']);
    expect(chat.conversations['calc_bob']!.unreadBy, ['bob']);
  });

  testWidgets('"Réinitialiser" in the filter sheet clears every filter', (tester) async {
    await h.signIn(tester);
    final provider = marketProvider(FakeArticleRepo([
      article('a', title: 'Livre', price: 10),
      article('b', title: 'Lampe', price: 30),
    ]));
    await pumpMarket(tester, h, provider, const VenteDonListScreen());
    await tester.tap(find.byKey(const Key('open-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sort-priceDesc')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('apply-filters')));
    await tester.tap(find.byKey(const Key('apply-filters')));
    await tester.pumpAndSettle();
    expect(provider.filters.advancedCount, greaterThan(0));

    await tester.tap(find.byKey(const Key('open-filters')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('reset-filters')));
    await tester.tap(find.byKey(const Key('reset-filters')));
    await tester.pumpAndSettle();
    expect(provider.filters.advancedCount, 0);
  });
}
