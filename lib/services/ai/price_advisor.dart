import '../../core/utils/article_search.dart';
import '../../models/article_model.dart';

/// D'où vient le prix conseillé.
enum PriceAdviceSource {
  /// Articles au titre proche, dans la même catégorie.
  similar,

  /// Tous les articles en vente de la catégorie.
  category,

  /// Pas assez d'articles : prix habituel de la catégorie (occasion étudiante).
  reference,
}

/// Fourchette de prix conseillée, calculée sur des articles comparables.
class PriceAdvice {
  final double low;
  final double high;
  final double suggested;

  /// Nombre d'articles qui ont servi au calcul.
  final int basedOn;

  final PriceAdviceSource source;

  const PriceAdvice({
    required this.low,
    required this.high,
    required this.suggested,
    required this.basedOn,
    required this.source,
  });

  /// true si le calcul repose sur des articles au titre proche.
  bool get similarTitles => source == PriceAdviceSource.similar;

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

/// Prix habituels d'occasion entre étudiants (DT) : bas, conseillé, haut.
/// Utilisés quand il n'y a pas encore d'articles comparables.
const Map<String, (double, double, double)> kReferencePrices = {
  'Livres': (10, 15, 30),
  'Électronique': (30, 60, 150),
  'Vêtements': (10, 20, 40),
  'Mobilier': (20, 40, 80),
  'Autre': (5, 15, 30),
};

/// Prix conseillé pour un article de [category] intitulé [title], d'après les
/// articles en vente (pas les dons) de [market] : d'abord les titres proches
/// (au moins 1), sinon toute la catégorie (au moins 2), sinon le prix
/// habituel de la catégorie ([kReferencePrices]).
PriceAdvice advisePrice({
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
  final PriceAdviceSource source;
  if (similar.isNotEmpty) {
    basis = similar;
    source = PriceAdviceSource.similar;
  } else if (forSale.length >= 2) {
    basis = forSale;
    source = PriceAdviceSource.category;
  } else {
    final (low, suggested, high) = kReferencePrices[category] ?? kReferencePrices['Autre']!;
    return PriceAdvice(
        low: low, high: high, suggested: suggested, basedOn: 0, source: PriceAdviceSource.reference);
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
    source: source,
  );
}
