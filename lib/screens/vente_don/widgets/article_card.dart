import 'package:flutter/material.dart';

import '../../../core/constants/layout.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/geo.dart';
import '../../../models/article_model.dart';
import '../../../widgets/photo_card.dart';
import '../../../widgets/status_chip.dart';

/// Hauteur de la photo d'une carte d'article.
const double kArticleImageHeight = 110;

/// Hauteur totale d'une cellule de la grille (grandit avec la taille du texte).
double articleCardHeight(BuildContext context) =>
    kArticleImageHeight + 24 + MediaQuery.textScalerOf(context).scale(104);

/// Nombre de colonnes de la grille pour une largeur donnée.
int articleGridColumns(double width) => width >= kCompactBreakpoint ? 3 : 2;

/// Puce d'état d'un article : Réservé, Terminé, Don ou Vente.
StatusChip articleStatusChip(ArticleModel a) {
  return switch (a.status) {
    ArticleStatus.reserved => const StatusChip(label: 'Réservé', style: StatusChipStyle.warning),
    ArticleStatus.done => const StatusChip(label: 'Terminé', style: StatusChipStyle.neutral),
    ArticleStatus.available => a.isFree
        ? const StatusChip(label: 'Don', style: StatusChipStyle.success)
        : const StatusChip(label: 'Vente'),
  };
}

/// Carte d'un article dans les grilles Vente & Don (liste, favoris, mes
/// articles) : photo, puce d'état, cœur, titre, prix et catégorie / distance.
class ArticleCard extends StatelessWidget {
  final ArticleModel article;
  final VoidCallback? onTap;
  final double? distanceKm;
  final bool showHeart;
  final bool favorite;
  final VoidCallback? onHeart;

  const ArticleCard({
    super.key,
    required this.article,
    this.onTap,
    this.distanceKm,
    this.showHeart = false,
    this.favorite = false,
    this.onHeart,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final d = distanceKm;
    final footer = [
      article.category,
      if (d != null) formatDistance(d),
    ].join(' · ');

    return Semantics(
      label: '${article.title}, ${article.priceLabel}',
      child: PhotoCard(
        key: ValueKey('article-${article.id}'),
        imageHeight: kArticleImageHeight,
        imageUrl: article.coverUrl,
        placeholderIcon: Icons.shopping_bag_outlined,
        chip: articleStatusChip(article),
        showHeart: showHeart,
        favorite: favorite,
        onHeart: onHeart,
        title: article.title,
        meta: Text(
          article.priceLabel,
          maxLines: 1,
          style: text.titleSmall?.copyWith(color: article.isFree ? t.success : t.primary),
        ),
        footer: Row(
          children: [
            Icon(d != null ? Icons.place_outlined : Icons.sell_outlined, size: 14, color: t.textSecondary),
            const SizedBox(width: 4),
            Expanded(
              child: Text(footer, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.labelMedium),
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

/// Grille d'articles en sliver (colonnes selon la largeur).
class ArticleSliverGrid extends StatelessWidget {
  final List<ArticleModel> articles;
  final Widget Function(BuildContext context, ArticleModel article) itemBuilder;

  const ArticleSliverGrid({super.key, required this.articles, required this.itemBuilder});

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(builder: (context, constraints) {
      return SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: articleGridColumns(constraints.crossAxisExtent),
          mainAxisSpacing: kCardGap,
          crossAxisSpacing: kCardGap,
          mainAxisExtent: articleCardHeight(context),
        ),
        delegate: SliverChildBuilderDelegate(
          (context, i) => itemBuilder(context, articles[i]),
          childCount: articles.length,
        ),
      );
    });
  }
}
