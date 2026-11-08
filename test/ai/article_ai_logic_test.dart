import 'package:campusconnect/models/article_model.dart';
import 'package:campusconnect/services/ai/article_ai.dart';
import 'package:campusconnect/services/ai/category_mapper.dart';
import 'package:campusconnect/services/ai/moderation.dart';
import 'package:campusconnect/services/ai/price_advisor.dart';
import 'package:campusconnect/services/ai/recommender.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/articles.dart';

void main() {
  group('suggestCategory (photo → catégorie)', () {
    test('a book photo suggests Livres with French keywords', () {
      final s = suggestCategory(const [
        ImageTag('Book', 0.92),
        ImageTag('Paper', 0.71),
        ImageTag('Wood', 0.66),
        ImageTag('Font', 0.6),
      ])!;
      expect(s.category, 'Livres');
      expect(s.confidence, 0.92);
      expect(s.keywords, ['livre', 'papier']);
    });

    test('scores add up per category', () {
      final s = suggestCategory(const [
        ImageTag('Desk', 0.6),
        ImageTag('Lamp', 0.58),
        ImageTag('Laptop', 0.7),
      ])!;
      expect(s.category, 'Mobilier'); // 1,18 contre 0,70
    });

    test('nothing sure enough → null', () {
      expect(suggestCategory(const [ImageTag('Sky', 0.9)]), isNull);
      expect(suggestCategory(const [ImageTag('Book', 0.4)]), isNull);
      expect(suggestCategory(const []), isNull);
    });

    test('labelsForSearch keeps confident, specific labels', () {
      expect(
        labelsForSearch(const [ImageTag('Book', 0.9), ImageTag('Wood', 0.8), ImageTag('Paper', 0.3)]),
        ['book'],
      );
    });
  });

  group('advisePrice', () {
    final market = [
      article('1', title: 'Calculatrice scientifique Casio', category: 'Électronique', price: 30),
      article('2', title: 'Calculatrice graphique', category: 'Électronique', price: 50),
      article('3', title: 'Casque audio', category: 'Électronique', price: 40),
      article('4', title: 'Clé USB', category: 'Électronique', price: 10),
      article('5', title: 'Calculatrice offerte', category: 'Électronique', price: null),
      article('6', title: 'Livre Java', category: 'Livres', price: 15),
    ];

    test('similar titles first, gifts ignored', () {
      final a = advisePrice(title: 'Calculatrice TI-83', category: 'Électronique', market: market);
      expect(a.similarTitles, isTrue);
      expect(a.basedOn, 2);
      expect(a.low, 35);
      expect(a.high, 45);
      expect(a.suggested, 40);
      expect(a.label, '35 à 45 DT');
    });

    test('falls back to the whole category', () {
      final a = advisePrice(title: 'Souris sans fil', category: 'Électronique', market: market);
      expect(a.similarTitles, isFalse);
      expect(a.basedOn, 4);
      expect(a.suggested, 35);
    });

    test('one similar title is enough', () {
      final a = advisePrice(title: 'Livre C', category: 'Livres', market: market);
      expect(a.source, PriceAdviceSource.similar);
      expect(a.basedOn, 1);
      expect(a.label, '15 DT');
    });

    test('no comparable article → usual price of the category', () {
      final a = advisePrice(title: 'Bureau', category: 'Mobilier', market: market);
      expect(a.source, PriceAdviceSource.reference);
      expect(a.basedOn, 0);
      expect(a.label, '20 à 80 DT');
      expect(a.suggested, 40);
      expect(advisePrice(title: 'x', category: 'Inconnue', market: const []).label, '5 à 30 DT');
    });

    test('the article being edited is not compared with itself', () {
      final two = [market[0], market[1]];
      expect(advisePrice(title: 'Calculatrice', category: 'Électronique', market: two).basedOn, 2);
      expect(advisePrice(title: 'Calculatrice', category: 'Électronique', market: two, excludeId: '1').basedOn, 1);
    });
  });

  group('moderateArticle', () {
    ModerationResult check(String title, [String description = 'Objet en bon état.', double? price = 10]) =>
        moderateArticle(title: title, description: description, category: 'Autre', price: price);

    test('a normal article passes', () {
      expect(check('Livre de cuisine').ok, isTrue);
      expect(check('Corrigés des exercices de maths').ok, isTrue);
    });

    test('forbidden items and insults are blocked (accents ignored)', () {
      expect(check('Vends médicaments').blocked, isTrue);
      expect(check('Pistolet à billes').blocked, isTrue);
      expect(check('Sujet examen final', 'Avec les réponses').blocked, isTrue);
      expect(check('Livre', 'Le vendeur précédent est un connard').blocked, isTrue);
      expect(check('Vends médicaments').messages(ModerationLevel.block).single, contains('médicaments'));
    });

    test('contact details, all caps and odd prices only warn', () {
      final phone = check('Chaise', 'Appelle-moi au 22 123 456');
      expect(phone.blocked, isFalse);
      expect(phone.hasWarnings, isTrue);
      expect(check('Lampe', 'Écris à moi@mail.com').hasWarnings, isTrue);
      expect(check('Lampe', 'Voir www.site.tn').hasWarnings, isTrue);
      expect(check('SUPER LAMPE NEUVE').hasWarnings, isTrue);
      expect(check('Voiture', 'Objet', 12000).hasWarnings, isTrue);
      expect(
        moderateArticle(title: 'Téléphone', description: 'Bon état', category: 'Électronique', price: 1)
            .hasWarnings,
        isTrue,
      );
    });
  });

  group('recommendArticles', () {
    final now = DateTime(2026, 11, 6);
    final all = [
      article('fav', title: 'Livre de Java', category: 'Livres', favoritedBy: const ['me']),
      article('python', title: 'Livre Python', category: 'Livres', createdAt: DateTime(2026, 11, 5)),
      article('math', title: 'Cours de maths', category: 'Livres', createdAt: DateTime(2026, 10, 1)),
      article('lamp', title: 'Lampe', category: 'Mobilier'),
      article('mine', title: 'Livre Java avancé', category: 'Livres', ownerId: 'me'),
      article('done', title: 'Livre Java vendu', category: 'Livres', status: ArticleStatus.done),
    ];

    test('nothing liked or viewed → nothing', () {
      expect(recommendArticles(all, 'someone', now: now), isEmpty);
    });

    test('close to favorites first, never mine, done or already liked', () {
      final ids = [for (final a in recommendArticles(all, 'me', now: now)) a.id];
      expect(ids, ['python', 'math']);
    });

    test('viewed articles teach too but are not shown again', () {
      final ids = [
        for (final a in recommendArticles(all, 'other', viewedIds: const ['lamp'], now: now)) a.id,
      ];
      expect(ids, isEmpty); // seule la lampe est en Mobilier, déjà vue
      final more = [
        ...all,
        article('desk', title: 'Lampe de bureau', category: 'Mobilier'),
      ];
      expect([for (final a in recommendArticles(more, 'other', viewedIds: const ['lamp'], now: now)) a.id],
          ['desk']);
    });

    test('photo labels count', () {
      final withLabels = [
        article('fav', title: 'A', category: 'Autre', favoritedBy: const ['me'], labels: const ['guitar']),
        article('g', title: 'B', category: 'Mobilier', labels: const ['guitar']),
        article('x', title: 'C', category: 'Mobilier'),
      ];
      expect([for (final a in recommendArticles(withLabels, 'me', now: now)) a.id], ['g']);
    });
  });

  group('photo search', () {
    test('labelSimilarity is a Jaccard index', () {
      expect(labelSimilarity(['book', 'paper'], ['book']), 0.5);
      expect(labelSimilarity(['book'], const []), 0);
      expect(labelSimilarity(['Book'], ['book']), 1);
    });

    test('rankByPhoto keeps lookalikes, best first', () {
      final ranked = rankByPhoto([
        article('a', labels: const ['book']),
        article('b', labels: const ['book', 'paper']),
        article('c', labels: const ['lamp']),
        article('d'),
      ], ['book', 'paper']);
      expect([for (final a in ranked) a.id], ['b', 'a']);
    });
  });

  test('the local writer composes a description without price or contact', () async {
    const w = LocalDescriptionWriter();
    final sale = await w.write(const DescriptionRequest(
        title: 'Calculatrice scientifique', category: 'Électronique', price: 35, keywords: ['calculatrice', 'écran']));
    expect(sale, startsWith('Je vends calculatrice scientifique'));
    expect(sale, contains('Sur la photo : écran.'));
    expect(sale, contains('testé'));
    expect(sale, isNot(contains('35')));
    expect(moderateArticle(title: 'Calculatrice scientifique', description: sale, category: 'Électronique', price: 35).blocked, isFalse);

    final gift = await w.write(const DescriptionRequest(title: 'Veste', category: 'Vêtements'));
    expect(gift, startsWith('Je donne veste'));
    expect(gift, contains('Gratuit'));
  });
}
