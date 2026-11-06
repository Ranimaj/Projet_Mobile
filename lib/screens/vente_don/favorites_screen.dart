import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/layout.dart';
import '../../models/article_model.dart';
import '../../providers/article_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/empty_state.dart';
import 'article_detail_screen.dart';
import 'widgets/article_card.dart';

/// Articles mis en favori par l'utilisateur connecté (cœur sur une carte ou
/// sur le détail). Le cœur retire l'article de la liste.
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ArticleProvider>();
    final uid = context.watch<AuthProvider>().currentUser?.id;
    final List<ArticleModel> favorites = uid == null ? const [] : provider.favoritesOf(uid);

    return Scaffold(
      appBar: AppBar(title: const Text('Mes favoris')),
      body: RefreshIndicator(
        onRefresh: provider.load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (favorites.isEmpty)
              const SliverToBoxAdapter(
                child: EmptyState(
                  icon: Icons.favorite_border_rounded,
                  title: 'Aucun favori',
                  subtitle: 'Touche le cœur d\'un article pour le retrouver ici.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(kPagePadding),
                sliver: ArticleSliverGrid(
                  articles: favorites,
                  itemBuilder: (context, a) => ArticleCard(
                    article: a,
                    distanceKm: provider.distanceKmTo(a),
                    showHeart: true,
                    favorite: true,
                    onHeart: () => provider.toggleFavorite(a.id, uid!),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ArticleDetailScreen(article: a)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
