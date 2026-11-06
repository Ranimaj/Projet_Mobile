import '../../models/article_model.dart';
import 'geo.dart';

/// Ordre d'affichage de la liste Vente & Don.
enum ArticleSort { recent, priceAsc, priceDesc, nearest, popular }

extension ArticleSortLabel on ArticleSort {
  String get label => switch (this) {
        ArticleSort.recent => 'Plus récents',
        ArticleSort.priceAsc => 'Prix croissant',
        ArticleSort.priceDesc => 'Prix décroissant',
        ArticleSort.nearest => 'Plus proches',
        ArticleSort.popular => 'Plus vus',
      };
}

/// Filtres combinés de la recherche Vente & Don (fonctionnalité avancée 2).
/// Tous les critères se cumulent (ET logique).
class ArticleFilters {
  final String query;
  final String? category;
  final bool freeOnly;
  final double? minPrice;
  final double? maxPrice;

  /// Rayon maximal en km autour de l'utilisateur (null = partout).
  final double? maxDistanceKm;
  final ArticleSort sort;

  const ArticleFilters({
    this.query = '',
    this.category,
    this.freeOnly = false,
    this.minPrice,
    this.maxPrice,
    this.maxDistanceKm,
    this.sort = ArticleSort.recent,
  });

  static const none = ArticleFilters();

  bool get hasPriceRange => minPrice != null || maxPrice != null;

  /// Nombre de filtres « avancés » actifs (prix, distance, tri) — sert à la
  /// pastille du bouton filtre ; la recherche et les puces ne comptent pas.
  int get advancedCount =>
      (hasPriceRange ? 1 : 0) + (maxDistanceKm != null ? 1 : 0) + (sort != ArticleSort.recent ? 1 : 0);

  bool get isEmpty =>
      query.trim().isEmpty && category == null && !freeOnly && advancedCount == 0;

  ArticleFilters copyWith({
    String? query,
    String? category,
    bool clearCategory = false,
    bool? freeOnly,
    double? minPrice,
    double? maxPrice,
    bool clearPrice = false,
    double? maxDistanceKm,
    bool clearDistance = false,
    ArticleSort? sort,
  }) {
    return ArticleFilters(
      query: query ?? this.query,
      category: clearCategory ? null : (category ?? this.category),
      freeOnly: freeOnly ?? this.freeOnly,
      minPrice: clearPrice ? null : (minPrice ?? this.minPrice),
      maxPrice: clearPrice ? null : (maxPrice ?? this.maxPrice),
      maxDistanceKm: clearDistance ? null : (maxDistanceKm ?? this.maxDistanceKm),
      sort: sort ?? this.sort,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ArticleFilters &&
      other.query == query &&
      other.category == category &&
      other.freeOnly == freeOnly &&
      other.minPrice == minPrice &&
      other.maxPrice == maxPrice &&
      other.maxDistanceKm == maxDistanceKm &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(query, category, freeOnly, minPrice, maxPrice, maxDistanceKm, sort);
}

const _accents = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a',
  'ç': 'c',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'î': 'i', 'ï': 'i', 'í': 'i', 'ì': 'i',
  'ô': 'o', 'ö': 'o', 'ó': 'o', 'ò': 'o', 'õ': 'o',
  'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
  'ÿ': 'y', 'ñ': 'n', 'œ': 'oe', 'æ': 'ae',
};

/// Minuscules, sans accents ni ponctuation, espaces simples.
String normalizeSearch(String input) {
  final lower = input.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(_accents[ch] ?? ch);
  }
  return buffer
      .toString()
      .replaceAll(RegExp(r"[^a-z0-9]+"), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

/// Score de pertinence de [article] pour [query] normalisée : 0 si un mot
/// manque. Chaque mot doit apparaître dans le titre, la description ou la
/// catégorie (début de mot accepté : « velo » trouve « vélos ») ; le titre
/// pèse plus lourd que la catégorie, elle-même plus que la description.
int relevanceScore(ArticleModel article, String query) {
  final words = normalizeSearch(query).split(' ').where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return 1;
  final title = ' ${normalizeSearch(article.title)}';
  final category = ' ${normalizeSearch(article.category)}';
  final description = ' ${normalizeSearch(article.description)}';
  var score = 0;
  for (final w in words) {
    final needle = ' $w';
    if (title.contains(needle)) {
      score += 3;
    } else if (category.contains(needle)) {
      score += 2;
    } else if (description.contains(needle)) {
      score += 1;
    } else if (title.contains(w) || description.contains(w)) {
      score += 1; // milieu de mot : « phone » dans « smartphone »
    } else {
      return 0;
    }
  }
  return score;
}

/// Applique [filters] à [articles] et renvoie la liste triée. [from] est la
/// position de l'utilisateur ; sans elle, le filtre de distance est ignoré et
/// le tri « Plus proches » retombe sur « Plus récents ».
List<ArticleModel> filterArticles(
  Iterable<ArticleModel> articles,
  ArticleFilters filters, {
  GeoPoint2? from,
}) {
  final scores = <String, int>{};
  final distances = <String, double?>{};
  final hasQuery = filters.query.trim().isNotEmpty;

  final result = <ArticleModel>[];
  for (final a in articles) {
    if (filters.category != null && a.category != filters.category) continue;
    if (filters.freeOnly && !a.isFree) continue;
    final value = a.price ?? 0;
    if (filters.minPrice != null && value < filters.minPrice!) continue;
    if (filters.maxPrice != null && value > filters.maxPrice!) continue;

    final d = a.distanceKmFrom(from);
    distances[a.id] = d;
    if (filters.maxDistanceKm != null && from != null) {
      if (d == null || d > filters.maxDistanceKm!) continue;
    }

    if (hasQuery) {
      final s = relevanceScore(a, filters.query);
      if (s == 0) continue;
      scores[a.id] = s;
    }
    result.add(a);
  }

  int byDate(ArticleModel a, ArticleModel b) => b.createdAt.compareTo(a.createdAt);

  int compare(ArticleModel a, ArticleModel b) {
    switch (filters.sort) {
      case ArticleSort.priceAsc:
        final c = (a.price ?? 0).compareTo(b.price ?? 0);
        return c != 0 ? c : byDate(a, b);
      case ArticleSort.priceDesc:
        final c = (b.price ?? 0).compareTo(a.price ?? 0);
        return c != 0 ? c : byDate(a, b);
      case ArticleSort.popular:
        final c = b.viewCount.compareTo(a.viewCount);
        return c != 0 ? c : byDate(a, b);
      case ArticleSort.nearest:
        if (from != null) {
          final da = distances[a.id];
          final db = distances[b.id];
          if (da != null && db != null && da != db) return da.compareTo(db);
          if (da != null && db == null) return -1;
          if (da == null && db != null) return 1;
        }
        return byDate(a, b);
      case ArticleSort.recent:
        // Avec une recherche, les plus pertinents d'abord.
        if (hasQuery) {
          final c = (scores[b.id] ?? 0).compareTo(scores[a.id] ?? 0);
          if (c != 0) return c;
        }
        return byDate(a, b);
    }
  }

  result.sort(compare);
  return result;
}
