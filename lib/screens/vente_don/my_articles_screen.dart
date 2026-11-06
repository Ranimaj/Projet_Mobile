import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/layout.dart';
import '../../models/article_model.dart';
import '../../providers/article_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/filter_chip_pill.dart';
import '../../widgets/stat_tile.dart';
import 'article_detail_screen.dart';
import 'article_form_screen.dart';
import 'widgets/article_card.dart';

/// Articles publiés par l'utilisateur, y compris réservés et terminés, avec
/// un filtre par état et quelques chiffres (vues, favoris).
class MyArticlesScreen extends StatefulWidget {
  const MyArticlesScreen({super.key});

  @override
  State<MyArticlesScreen> createState() => _MyArticlesScreenState();
}

class _MyArticlesScreenState extends State<MyArticlesScreen> {
  ArticleStatus? _status;

  static const _labels = {
    null: 'Tous',
    ArticleStatus.available: 'Disponibles',
    ArticleStatus.reserved: 'Réservés',
    ArticleStatus.done: 'Terminés',
  };

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ArticleProvider>();
    final uid = context.watch<AuthProvider>().currentUser?.id;
    final List<ArticleModel> mine = uid == null ? const [] : provider.mine(uid);
    final shown = _status == null ? mine : mine.where((a) => a.status == _status).toList();
    final views = mine.fold<int>(0, (sum, a) => sum + a.viewCount);
    final likes = mine.fold<int>(0, (sum, a) => sum + a.favoritedBy.length);

    return Scaffold(
      appBar: AppBar(title: const Text('Mes articles')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Publier un article',
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const ArticleFormScreen())),
        child: const Icon(Icons.add_rounded),
      ),
      body: RefreshIndicator(
        onRefresh: provider.load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(kPagePadding, 16, kPagePadding, 8),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(child: StatTile(value: '${mine.length}', label: 'Publiés')),
                    const SizedBox(width: kCardGap),
                    Expanded(child: StatTile(value: '$views', label: 'Vues')),
                    const SizedBox(width: kCardGap),
                    Expanded(child: StatTile(value: '$likes', label: 'Favoris')),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
                  children: [
                    for (final entry in _labels.entries) ...[
                      FilterChipPill(
                        label: entry.value,
                        selected: _status == entry.key,
                        onTap: () => setState(() => _status = entry.key),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ),
            if (shown.isEmpty)
              SliverToBoxAdapter(
                child: EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: mine.isEmpty ? 'Aucun article publié' : 'Aucun article dans cet état',
                  subtitle: mine.isEmpty
                      ? 'Publie ton premier objet à vendre ou à donner.'
                      : 'Choisis un autre filtre.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(kPagePadding, 0, kPagePadding, 96),
                sliver: ArticleSliverGrid(
                  articles: shown,
                  itemBuilder: (context, a) => ArticleCard(
                    article: a,
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
