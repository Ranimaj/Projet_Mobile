import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/annonce_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/offline_banner.dart';
import '../../widgets/status_badge.dart';
import 'add_annonce_screen.dart';
import 'annonce_detail_screen.dart';

/// BF6/BF7 — fil d'annonces campus, épinglage automatique des officielles.
class AnnoncesListScreen extends StatefulWidget {
  const AnnoncesListScreen({super.key});

  @override
  State<AnnoncesListScreen> createState() => _AnnoncesListScreenState();
}

class _AnnoncesListScreenState extends State<AnnoncesListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<AnnonceProvider>().load());
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AnnonceProvider>();
    final isGuest = context.watch<AuthProvider>().status != AuthStatus.authenticated;

    return Scaffold(
      appBar: AppBar(title: const Text('Annonces')),
      floatingActionButton: isGuest
          ? null
          : FloatingActionButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const AddAnnonceScreen())),
              child: const Icon(Icons.add_rounded),
            ),
      body: SafeArea(
        child: Column(
          children: [
            const OfflineBanner(),
            SizedBox(
              height: 46,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                children: [
                  _Chip(label: 'Toutes', selected: provider.categoryFilter == null,
                      onTap: () => provider.setCategoryFilter(null)),
                  const SizedBox(width: 8),
                  ...AppConstants.annonceCategories.map((c) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _Chip(
                          label: c,
                          selected: provider.categoryFilter == c,
                          onTap: () => provider.setCategoryFilter(provider.categoryFilter == c ? null : c),
                        ),
                      )),
                ],
              ),
            ),
            Expanded(
              child: provider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : provider.items.isEmpty
                      ? const EmptyState(
                          icon: Icons.campaign_outlined,
                          title: 'Aucune annonce',
                          subtitle: "Les annonces officielles et du campus s'afficheront ici.",
                        )
                      : RefreshIndicator(
                          onRefresh: provider.load,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 90),
                            itemCount: provider.items.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final a = provider.items[i];
                              final isOfficial = a.category == 'Officielle';
                              return GestureDetector(
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => AnnonceDetailScreen(annonce: a)),
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: isOfficial ? const Color(0xFFFFF7ED) : Colors.white,
                                    border: Border.all(color: isOfficial ? const Color(0xFFFED7AA) : AppColors.border),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(children: [
                                        if (a.isPinned)
                                          Text('ÉPINGLÉ · ${a.category.toUpperCase()}',
                                              style: const TextStyle(
                                                  fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.accent2))
                                        else
                                          Text(a.category.toUpperCase(),
                                              style: const TextStyle(
                                                  fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
                                        if (a.isUrgent) ...[
                                          const SizedBox(width: 6),
                                          StatusBadge.danger('URGENT'),
                                        ],
                                      ]),
                                      const SizedBox(height: 5),
                                      Text(a.title,
                                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 4),
                                      Text('${a.authorName} · ${a.commentCount} commentaires',
                                          style: Theme.of(context).textTheme.bodyMedium),
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

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});

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
        child: Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: selected ? Colors.white : AppColors.textSecondary)),
      ),
    );
  }
}
