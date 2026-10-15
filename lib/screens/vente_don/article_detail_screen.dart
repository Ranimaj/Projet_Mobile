import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/article_model.dart';
import '../../providers/article_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/primary_button.dart';

/// BF6 — détail d'un article : voir, modifier son propre article, marquer
/// réservé/vendu, ajouter aux favoris.
class ArticleDetailScreen extends StatelessWidget {
  final ArticleModel article;
  const ArticleDetailScreen({super.key, required this.article});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isOwner = auth.currentUser?.id == article.ownerId;
    final isFav = auth.currentUser != null && article.favoritedBy.contains(auth.currentUser!.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(article.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (!isOwner && auth.currentUser != null)
            IconButton(
              icon: Icon(isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: isFav ? AppColors.danger : null),
              onPressed: () => context
                  .read<ArticleProvider>()
                  .toggleFavorite(article.id, auth.currentUser!.id),
            ),
          if (isOwner)
            PopupMenuButton<String>(
              onSelected: (value) async {
                final provider = context.read<ArticleProvider>();
                if (value == 'reserve') await provider.markAsReserved(article.id);
                if (value == 'done') await provider.markAsDone(article.id);
                if (value == 'delete') {
                  await provider.deleteArticle(article.id);
                  if (context.mounted) Navigator.pop(context);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'reserve', child: Text('Marquer comme réservé')),
                PopupMenuItem(value: 'done', child: Text('Marquer comme vendu/donné')),
                PopupMenuItem(value: 'delete', child: Text('Supprimer')),
              ],
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (article.imageUrls.isNotEmpty)
              SizedBox(
                height: 220,
                child: PageView(
                  children: article.imageUrls
                      .map((url) => CachedNetworkImage(imageUrl: url, fit: BoxFit.cover))
                      .toList(),
                ),
              )
            else
              Container(height: 180, color: AppColors.categoryTints.first,
                  child: const Center(child: Icon(Icons.image_rounded, size: 42, color: Colors.white))),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (article.status == ArticleStatus.reserved) StatusBadge.warning('Réservé'),
                      if (article.status == ArticleStatus.done) StatusBadge.info('Terminé'),
                      if (article.pendingSync) ...[
                        const SizedBox(width: 6),
                        StatusBadge.warning('En attente de synchro'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(article.title, style: Theme.of(context).textTheme.displayMedium),
                  const SizedBox(height: 6),
                  Text(
                    article.isFree ? 'Gratuit' : '${article.price!.toStringAsFixed(0)} DT',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.primary),
                  ),
                  const SizedBox(height: 16),
                  Text('Description', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(article.description, style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(Icons.person_outline_rounded, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text('Publié par ${article.ownerName}', style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                  if (!isOwner) ...[
                    const SizedBox(height: 24),
                    PrimaryButton(
                      label: 'Contacter le vendeur',
                      icon: Icons.chat_bubble_outline_rounded,
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Ouverture de la conversation…')),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
