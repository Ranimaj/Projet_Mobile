import '../../core/utils/article_search.dart';
import '../../models/article_model.dart';

/// Fourchette de prix conseillée, calculée sur des articles comparables.
class PriceAdvice {
  final double low;
  final double high;
  final double suggested;

  /// Nombre d'articles qui ont servi au calcul.
  final int basedOn;

  /// true si le calcul repose sur des articles au titre proche (sinon sur
  /// toute la catégorie).
  final bool similarTitles;

  const PriceAdvice({
    required this.low,
    required this.high,
    required this.suggested,
    required this.basedOn,
    required this.similarTitles,
  });

  String get label => low == high ? '${low.round()} DT' : '${low.round()} à ${high.round()} DT';
}

const _stopWords = {
  'de', 'des', 'du', 'la', 'le', 'les', 'un', 'une', 'et', 'en', 'pour', 'avec', 'a', 'au',
  'aux', 'tres', 'bon', 'etat', 'neuf', 'neuve', 'taille',
};

Set<String> _tokens(String text) => normalizeSearch(text)
    .split(' ')
    .where((w) => w.length > 2 && !_stopWords.contains(w))
    .toSet();

double _quantile(List<double> sorted, double q) {
  if (sorted.length == 1) return sorted.first;
  final pos = (sorted.length - 1) * q;
  final lo = pos.floor();
  final hi = pos.ceil();
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - lo);
}

double _round(double v) => v < 20 ? v.roundToDouble() : (v / 5).round() * 5.0;

/// Prix conseillé pour un article de [category] intitulé [title], d'après les
/// articles en vente (pas les dons) de [market]. Priorité aux titres proches
/// (au moins 2), sinon toute la catégorie (au moins 3). Null sinon.
PriceAdvice? advisePrice({
  required String title,
  required String category,
  required Iterable<ArticleModel> market,
  String? excludeId,
}) {
  final forSale = market
      .where((a) => !a.isFree && a.id != excludeId && a.price != null && a.price! > 0)
      .where((a) => a.category == category)
      .toList();
  final words = _tokens(title);
  final similar = words.isEmpty
      ? <ArticleModel>[]
      : forSale.where((a) => _tokens(a.title).intersection(words).isNotEmpty).toList();

  final List<ArticleModel> basis;
  final bool bySimilarity;
  if (similar.length >= 2) {
    basis = similar;
    bySimilarity = true;
  } else if (forSale.length >= 3) {
    basis = forSale;
    bySimilarity = false;
  } else {
    return null;
  }
  final prices = [for (final a in basis) a.price!]..sort();
  final low = _round(_quantile(prices, 0.25));
  final high = _round(_quantile(prices, 0.75));
  final median = _round(_quantile(prices, 0.5));
  return PriceAdvice(
    low: low,
    high: high < low ? low : high,
    suggested: median,
    basedOn: basis.length,
    similarTitles: bySimilarity,
  );
}
