import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/layout.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/article_search.dart';
import '../../models/article_model.dart';
import '../../providers/article_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/filter_chip_pill.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/round_icon_button.dart';
import '../../widgets/skeleton_box.dart';
import 'article_detail_screen.dart';
import 'article_form_screen.dart';
import 'conversations_screen.dart';
import 'favorites_screen.dart';
import 'my_articles_screen.dart';
import 'widgets/article_card.dart';
import 'widgets/article_filter_sheet.dart';

/// BF4/BF5 — Gestion Vente & Don : grille d'articles avec photos, recherche
/// intelligente, filtres combinés (catégorie, gratuit, prix, distance, tri),
/// favoris, messages et articles de l'utilisateur.
class VenteDonListScreen extends StatefulWidget {
  const VenteDonListScreen({super.key});

  @override
  State<VenteDonListScreen> createState() => _VenteDonListScreenState();
}

class _VenteDonListScreenState extends State<VenteDonListScreen> {
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    final provider = context.read<ArticleProvider>();
    _search.text = provider.searchQuery;
    WidgetsBinding.instance.addPostFrameCallback((_) => provider.load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _push(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  Future<void> _openFilters(ArticleProvider provider) async {
    final result = await showArticleFilterSheet(
      context,
      current: provider.filters,
      highestPrice: provider.highestPrice,
      hasPosition: provider.userPosition != null,
      onLocate: () async {
        final ok = await provider.locateUser();
        if (!mounted) return ok;
        final error = provider.locationError;
        if (!ok && error != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
        }
        return ok;
      },
    );
    if (result != null) provider.setFilters(result);
  }

  void _clearSearch(ArticleProvider provider) {
    _search.clear();
    provider.setSearch('');
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ArticleProvider>();
    final auth = context.watch<AuthProvider>();
    final user = auth.status == AuthStatus.authenticated ? auth.currentUser : null;
    final filters = provider.filters;
    final items = provider.items;
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: t.background,
      floatingActionButton: user == null
          ? null
          : FloatingActionButton.extended(
              key: const Key('publish-article'),
              backgroundColor: t.primary,
              foregroundColor: t.onPrimary,
              onPressed: () => _push(const ArticleFormScreen()),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Publier'),
            ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: provider.load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(kPagePadding, 16, 12, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Vente & Don', style: text.headlineMedium),
                            const SizedBox(height: 2),
                            Text('Achète, vends ou donne sur le campus', style: text.bodyMedium),
                          ],
                        ),
                      ),
                      if (user != null) ...[
                        RoundIconButton(
                          key: const Key('open-favorites'),
                          icon: Icons.favorite_border_rounded,
                          tooltip: 'Mes favoris',
                          onPressed: () => _push(const FavoritesScreen()),
                        ),
                        RoundIconButton(
                          key: const Key('open-messages'),
                          icon: Icons.chat_bubble_outline_rounded,
                          tooltip: 'Mes messages',
                          onPressed: () => _push(const ConversationsScreen()),
                        ),
                        RoundIconButton(
                          key: const Key('open-my-articles'),
                          icon: Icons.inventory_2_outlined,
                          tooltip: 'Mes articles',
                          onPressed: () => _push(const MyArticlesScreen()),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: OfflineBanner()),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(kPagePadding, 16, kPagePadding, 4),
                sliver: SliverToBoxAdapter(
                  child: _SearchField(
                    controller: _search,
                    onChanged: provider.setSearch,
                    onClear: () => _clearSearch(provider),
                    onFilter: () => _openFilters(provider),
                    activeFilters: filters.advancedCount,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 56,
                  child: ListView(
                    key: const Key('category-chips'),
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
                    children: [
                      FilterChipPill(
                        label: 'Tous',
                        selected: filters.category == null && !filters.freeOnly,
                        onTap: () {
                          provider.setFilters(
                              filters.copyWith(clearCategory: true, freeOnly: false));
                        },
                      ),
                      const SizedBox(width: 8),
                      FilterChipPill(
                        label: 'Gratuit',
                        icon: Icons.volunteer_activism_outlined,
                        selected: filters.freeOnly,
                        onTap: provider.toggleFreeOnly,
                      ),
                      for (final c in AppConstants.articleCategories) ...[
                        const SizedBox(width: 8),
                        FilterChipPill(
                          label: c,
                          selected: filters.category == c,
                          onTap: () =>
                              provider.setCategoryFilter(filters.category == c ? null : c),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(kPagePadding, 4, kPagePadding, 8),
                sliver: SliverToBoxAdapter(
                  child: _ResultsBar(
                    count: items.length,
                    filters: filters,
                    onReset: filters.isEmpty
                        ? null
                        : () {
                            _search.clear();
                            provider.setFilters(ArticleFilters.none);
                          },
                  ),
                ),
              ),
              if (provider.isLoading && items.isEmpty)
                const SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: kPagePadding),
                  sliver: _LoadingGrid(),
                )
              else if (items.isEmpty)
                SliverToBoxAdapter(
                  child: filters.isEmpty
                      ? const EmptyState(
                          icon: Icons.storefront_outlined,
                          title: 'Aucun article pour le moment',
                          subtitle: 'Sois le premier à publier un article à vendre ou à donner !',
                        )
                      : const EmptyState(
                          icon: Icons.search_off_rounded,
                          title: 'Aucun résultat',
                          subtitle: 'Essaie d\'autres mots ou élargis les filtres.',
                        ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(kPagePadding, 0, kPagePadding, 96),
                  sliver: ArticleSliverGrid(
                    articles: items,
                    itemBuilder: (context, a) => _cardFor(context, a, provider, user?.id),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cardFor(BuildContext context, ArticleModel a, ArticleProvider provider, String? uid) {
    final liker = uid != null && uid != a.ownerId ? uid : null;
    return ArticleCard(
      article: a,
      distanceKm: provider.distanceKmTo(a),
      showHeart: liker != null,
      favorite: a.isFavoriteOf(uid),
      onHeart: liker == null ? null : () => provider.toggleFavorite(a.id, liker),
      onTap: () => _push(ArticleDetailScreen(article: a)),
    );
  }
}

/// Champ de recherche en pilule avec bouton filtre (pastille = filtres actifs).
class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onFilter;
  final int activeFilters;

  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.onFilter,
    required this.activeFilters,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 52,
      padding: const EdgeInsets.only(left: 18, right: 2),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(26),
        border: dark ? Border.all(color: t.outline) : null,
        boxShadow: dark ? null : t.cardShadow,
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 22, color: t.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              key: const Key('article-search'),
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: const InputDecoration(
                hintText: 'Rechercher un objet, une catégorie…',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, __) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Effacer',
                    icon: Icon(Icons.close_rounded, color: t.textSecondary),
                    onPressed: onClear,
                  ),
          ),
          RoundIconButton(
            key: const Key('open-filters'),
            icon: Icons.tune_rounded,
            tooltip: activeFilters > 0 ? 'Filtrer ($activeFilters actifs)' : 'Filtrer',
            style: activeFilters > 0 ? RoundButtonStyle.primary : RoundButtonStyle.soft,
            showDot: activeFilters > 0,
            onPressed: onFilter,
          ),
        ],
      ),
    );
  }
}

/// « 12 résultats · Prix croissant » + lien Effacer quand un filtre est actif.
class _ResultsBar extends StatelessWidget {
  final int count;
  final ArticleFilters filters;
  final VoidCallback? onReset;

  const _ResultsBar({required this.count, required this.filters, this.onReset});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final parts = <String>[
      count <= 1 ? '$count article' : '$count articles',
      if (filters.sort != ArticleSort.recent) filters.sort.label,
      if (filters.hasPriceRange)
        '${(filters.minPrice ?? 0).round()}–${filters.maxPrice == null ? '∞' : filters.maxPrice!.round()} DT',
      if (filters.maxDistanceKm != null) '≤ ${filters.maxDistanceKm!.round()} km',
    ];
    return Row(
      children: [
        Expanded(
          child: Text(parts.join(' · '),
              key: const Key('results-summary'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.labelMedium),
        ),
        if (onReset != null)
          TextButton(
            key: const Key('reset-all'),
            onPressed: onReset,
            child: const Text('Effacer les filtres'),
          ),
      ],
    );
  }
}

class _LoadingGrid extends StatelessWidget {
  const _LoadingGrid();

  @override
  Widget build(BuildContext context) {
    return ArticleSliverGrid(
      articles: List.generate(
        4,
        (i) => ArticleModel(
          id: 'skeleton-$i',
          ownerId: '',
          ownerName: '',
          title: '',
          description: '',
          category: '',
          createdAt: DateTime(2000),
        ),
      ),
      itemBuilder: (_, __) => const SkeletonBox(radius: 20),
    );
  }
}
