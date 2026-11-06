import 'package:campusconnect/core/utils/article_search.dart';
import 'package:campusconnect/core/utils/geo.dart';
import 'package:campusconnect/models/article_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/articles.dart';

const _campus = GeoPoint2(36.8992, 10.1897); // ESPRIT Ghazela
const _tunis = GeoPoint2(36.8065, 10.1815); // ~10 km

void main() {
  group('normalizeSearch', () {
    test('lowercases, strips accents and punctuation', () {
      expect(normalizeSearch('  Vélo  ÉLECTRIQUE, très bon état !'), 'velo electrique tres bon etat');
      expect(normalizeSearch('Cœur'), 'coeur');
      expect(normalizeSearch(''), '');
    });
  });

  group('relevanceScore', () {
    final calc = article('1',
        title: 'Calculatrice TI-83', description: 'Parfaite pour les maths', category: 'Électronique');

    test('every word must match somewhere', () {
      expect(relevanceScore(calc, 'calculatrice'), greaterThan(0));
      expect(relevanceScore(calc, 'calculatrice maths'), greaterThan(0));
      expect(relevanceScore(calc, 'calculatrice vélo'), 0);
    });

    test('accents and word prefixes are tolerated', () {
      expect(relevanceScore(calc, 'electronique'), greaterThan(0));
      expect(relevanceScore(calc, 'calcu'), greaterThan(0));
      expect(relevanceScore(calc, 'MATHS'), greaterThan(0));
    });

    test('title matches weigh more than description matches', () {
      expect(relevanceScore(calc, 'calculatrice'), greaterThan(relevanceScore(calc, 'maths')));
    });

    test('an empty query matches everything', () {
      expect(relevanceScore(calc, '   '), 1);
    });
  });

  group('filterArticles', () {
    final now = DateTime(2026, 11, 5);
    final book = article('book',
        title: 'Livre de Java',
        category: 'Livres',
        price: 15,
        createdAt: now.subtract(const Duration(days: 3)),
        viewCount: 2,
        latitude: _campus.latitude,
        longitude: _campus.longitude);
    final desk = article('desk',
        title: 'Bureau en bois',
        category: 'Mobilier',
        price: 80,
        createdAt: now.subtract(const Duration(days: 1)),
        viewCount: 9,
        latitude: _tunis.latitude,
        longitude: _tunis.longitude);
    final gift = article('gift',
        title: 'Manteau à donner',
        category: 'Vêtements',
        price: null,
        createdAt: now,
        viewCount: 5);
    final all = [book, desk, gift];

    List<String> ids(List<ArticleModel> l) => [for (final a in l) a.id];

    test('no filter: newest first', () {
      expect(ids(filterArticles(all, ArticleFilters.none)), ['gift', 'desk', 'book']);
    });

    test('category and free-only combine', () {
      expect(ids(filterArticles(all, const ArticleFilters(category: 'Livres'))), ['book']);
      expect(ids(filterArticles(all, const ArticleFilters(freeOnly: true))), ['gift']);
      expect(filterArticles(all, const ArticleFilters(category: 'Livres', freeOnly: true)), isEmpty);
    });

    test('price range treats a gift as 0 DT', () {
      expect(ids(filterArticles(all, const ArticleFilters(minPrice: 10, maxPrice: 50))), ['book']);
      expect(ids(filterArticles(all, const ArticleFilters(maxPrice: 20))), ['gift', 'book']);
      expect(ids(filterArticles(all, const ArticleFilters(minPrice: 50))), ['desk']);
    });

    test('distance filter needs a position and drops articles without one', () {
      const near = ArticleFilters(maxDistanceKm: 3);
      expect(ids(filterArticles(all, near, from: _campus)), ['book']);
      expect(ids(filterArticles(all, const ArticleFilters(maxDistanceKm: 25), from: _campus)),
          ['desk', 'book']);
      // Sans position : filtre ignoré.
      expect(filterArticles(all, near).length, 3);
    });

    test('sorts by price, popularity and distance', () {
      expect(ids(filterArticles(all, const ArticleFilters(sort: ArticleSort.priceAsc))),
          ['gift', 'book', 'desk']);
      expect(ids(filterArticles(all, const ArticleFilters(sort: ArticleSort.priceDesc))),
          ['desk', 'book', 'gift']);
      expect(ids(filterArticles(all, const ArticleFilters(sort: ArticleSort.popular))),
          ['desk', 'gift', 'book']);
      expect(ids(filterArticles(all, const ArticleFilters(sort: ArticleSort.nearest), from: _campus)),
          ['book', 'desk', 'gift']);
      // Sans position, « Plus proches » = plus récents.
      expect(ids(filterArticles(all, const ArticleFilters(sort: ArticleSort.nearest))),
          ['gift', 'desk', 'book']);
    });

    test('search ranks title matches first', () {
      final jacket = article('jacket',
          title: 'Veste', description: 'Comme un manteau léger', createdAt: now.add(const Duration(days: 1)));
      final result = filterArticles([...all, jacket], const ArticleFilters(query: 'manteau'));
      expect(ids(result), ['gift', 'jacket']);
    });

    test('everything combines: search + category + price + distance + sort', () {
      const f = ArticleFilters(
        query: 'bois',
        category: 'Mobilier',
        minPrice: 50,
        maxDistanceKm: 25,
        sort: ArticleSort.priceAsc,
      );
      expect(ids(filterArticles(all, f, from: _campus)), ['desk']);
      expect(filterArticles(all, f.copyWith(maxDistanceKm: 3), from: _campus), isEmpty);
    });
  });

  group('ArticleFilters', () {
    test('advancedCount counts price, distance and sort', () {
      expect(ArticleFilters.none.advancedCount, 0);
      expect(const ArticleFilters(query: 'x', category: 'Livres', freeOnly: true).advancedCount, 0);
      expect(
          const ArticleFilters(maxPrice: 20, maxDistanceKm: 5, sort: ArticleSort.popular).advancedCount, 3);
    });

    test('copyWith clears fields on demand', () {
      const f = ArticleFilters(category: 'Livres', minPrice: 1, maxPrice: 9, maxDistanceKm: 5);
      final cleared = f.copyWith(clearCategory: true, clearPrice: true, clearDistance: true);
      expect(cleared, ArticleFilters.none);
      expect(cleared.isEmpty, isTrue);
    });
  });

  group('geo', () {
    test('haversine distance between campus and downtown Tunis', () {
      expect(distanceKm(_tunis, _campus), closeTo(10.33, 0.05));
      expect(distanceKm(_campus, _campus), 0);
    });

    test('formatDistance', () {
      expect(formatDistance(0.093), '90 m');
      expect(formatDistance(0.001), '10 m');
      expect(formatDistance(1.24), '1,2 km');
      expect(formatDistance(10.33), '10 km');
    });
  });
}
