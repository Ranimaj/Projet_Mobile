import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../models/article_model.dart';
import '../../providers/article_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/status_badge.dart';
import 'add_article_screen.dart';
import 'article_detail_screen.dart';

/// BF4/BF5 — Gestion Vente & Don : grille d'articles + recherche + filtres.
class VenteDonListScreen extends StatefulWidget {
  const VenteDonListScreen({super.key});

  @override
  State<VenteDonListScreen> createState() => _VenteDonListScreenState();
}

class _VenteDonListScreenState extends State<VenteDonListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<ArticleProvider>().load());
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ArticleProvider>();
    final auth = context.watch<AuthProvider>();
    final isGuest = auth.status != AuthStatus.authenticated;

    return Scaffold(
      appBar: AppBar(title: const Text('Vente & Don')),
      floatingActionButton: isGuest
          ? null
          : FloatingActionButton(
              backgroundColor: AppColors.accent2,
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const AddArticleScreen())),
              child: const Icon(Icons.add_rounded, color: Colors.white),
            ),
      body: SafeArea(
        child: Column(
          children: [
            const OfflineBanner(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: TextField(
                onChanged: provider.setSearch,
                decoration: const InputDecoration(
                  hintText: 'Rechercher un article…',
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                ),
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _FilterChip(
                    label: 'Tous',
                    selected: provider.categoryFilter == null && !provider.showOnlyFree,
                    onTap: () {
                      provider.setCategoryFilter(null);
                      if (provider.showOnlyFree) provider.toggleFreeOnly();
                    },
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'Gratuit',
                    selected: provider.showOnlyFree,
                    onTap: provider.toggleFreeOnly,
                  ),
                  const SizedBox(width: 8),
                  ...AppConstants.articleCategories.map((c) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _FilterChip(
                          label: c,
                          selected: provider.categoryFilter == c,
                          onTap: () => provider.setCategoryFilter(provider.categoryFilter == c ? null : c),
                        ),
                      )),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: provider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : provider.items.isEmpty
                      ? const EmptyState(
                          icon: Icons.storefront_outlined,
                          title: 'Aucun article pour le moment',
                          subtitle: 'Soyez le premier à publier un article à vendre ou à donner !',
                        )
                      : RefreshIndicator(
                          onRefresh: provider.load,
                          child: GridView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 90),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 0.78,
                            ),
                            itemCount: provider.items.length,
                            itemBuilder: (context, i) {
                              final a = provider.items[i];
                              return GestureDetector(
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => ArticleDetailScreen(article: a)),
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: AppColors.border),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Container(
                                          color: AppColors.categoryTints[i % AppColors.categoryTints.length],
                                          width: double.infinity,
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(10),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(a.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                                            const SizedBox(height: 4),
                                            if (a.status == ArticleStatus.reserved)
                                              StatusBadge.warning('Réservé')
                                            else if (a.isFree)
                                              StatusBadge.success('Gratuit')
                                            else
                                              Text('${a.price!.toStringAsFixed(0)} DT',
                                                  style: const TextStyle(
                                                      fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
