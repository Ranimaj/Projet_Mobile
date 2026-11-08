import '../../core/utils/article_search.dart';
import '../../models/article_model.dart';

const _ignored = {'de', 'des', 'du', 'la', 'le', 'les', 'un', 'une', 'et', 'en', 'pour', 'avec', 'tres', 'bon', 'etat'};

Set<String> _words(ArticleModel a) => normalizeSearch('${a.title} ${a.category}')
    .split(' ')
    .where((w) => w.length > 2 && !_ignored.contains(w))
    .toSet();

/// Recommandations « Pour toi » : articles disponibles, d'autres vendeurs,
/// pas encore en favori, proches des favoris et des articles consultés de
/// [userId] (catégorie, mots du titre, étiquettes photo). Les favoris
/// comptent double. Renvoie au plus [limit] articles, mieux notés d'abord ;
/// vide tant que l'utilisateur n'a rien aimé ni consulté.
List<ArticleModel> recommendArticles(
  Iterable<ArticleModel> all,
  String userId, {
  Iterable<String> viewedIds = const [],
  int limit = 6,
  DateTime? now,
}) {
  final list = all.toList();
  final viewed = viewedIds.toSet();
  final liked = list.where((a) => a.favoritedBy.contains(userId)).toList();
  final seen = list.where((a) => viewed.contains(a.id) && !a.favoritedBy.contains(userId)).toList();
  if (liked.isEmpty && seen.isEmpty) return const [];

  final categoryWeight = <String, double>{};
  final wordWeight = <String, double>{};
  final labelWeight = <String, double>{};
  void learn(ArticleModel a, double w) {
    categoryWeight[a.category] = (categoryWeight[a.category] ?? 0) + w;
    for (final t in _words(a)) {
      wordWeight[t] = (wordWeight[t] ?? 0) + w;
    }
    for (final l in a.labels) {
      labelWeight[l] = (labelWeight[l] ?? 0) + w;
    }
  }

  for (final a in liked) {
    learn(a, 2);
  }
  for (final a in seen) {
    learn(a, 1);
  }

  final today = now ?? DateTime.now();
  final scored = <(ArticleModel, double)>[];
  for (final a in list) {
    if (a.ownerId == userId || !a.isAvailable || a.favoritedBy.contains(userId)) continue;
    if (viewed.contains(a.id)) continue;
    var score = (categoryWeight[a.category] ?? 0) * 2;
    for (final t in _words(a)) {
      score += wordWeight[t] ?? 0;
    }
    for (final l in a.labels) {
      score += (labelWeight[l] ?? 0) * 0.5;
    }
    if (score <= 0) continue;
    // Les annonces récentes passent devant à score égal.
    final ageDays = today.difference(a.createdAt).inDays.clamp(0, 60);
    score += (60 - ageDays) / 600;
    scored.add((a, score));
  }
  scored.sort((x, y) => y.$2.compareTo(x.$2));
  return [for (final (a, _) in scored.take(limit)) a];
}

/// Similarité (Jaccard) entre les étiquettes d'une photo cherchée et celles
/// d'un article. 0 si l'article n'a pas d'étiquettes.
double labelSimilarity(Iterable<String> query, Iterable<String> article) {
  final q = query.map((e) => e.toLowerCase()).toSet();
  final a = article.map((e) => e.toLowerCase()).toSet();
  if (q.isEmpty || a.isEmpty) return 0;
  return q.intersection(a).length / q.union(a).length;
}

/// Articles qui ressemblent à la photo cherchée, du plus proche au moins
/// proche (similarité > 0 uniquement).
List<ArticleModel> rankByPhoto(Iterable<ArticleModel> articles, List<String> queryLabels) {
  final scored = [
    for (final a in articles)
      if (labelSimilarity(queryLabels, a.labels) > 0) (a, labelSimilarity(queryLabels, a.labels)),
  ]..sort((x, y) => y.$2.compareTo(x.$2));
  return [for (final (a, _) in scored) a];
}
