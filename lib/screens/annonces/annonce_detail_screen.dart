import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/annonce_model.dart';
import '../../providers/annonce_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/status_badge.dart';

/// Détail d'une annonce + modération admin (épingler / supprimer).
class AnnonceDetailScreen extends StatelessWidget {
  final AnnonceModel annonce;
  const AnnonceDetailScreen({super.key, required this.annonce});

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AuthProvider>().currentUser?.role.name == 'admin';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Annonce'),
        actions: [
          if (isAdmin)
            PopupMenuButton<String>(
              onSelected: (value) async {
                final provider = context.read<AnnonceProvider>();
                if (value == 'pin') await provider.pinAnnonce(annonce.id, !annonce.isPinned);
                if (value == 'delete') {
                  await provider.deleteAnnonce(annonce.id);
                  if (context.mounted) Navigator.pop(context);
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'pin', child: Text(annonce.isPinned ? 'Désépingler' : 'Épingler')),
                const PopupMenuItem(value: 'delete', child: Text('Supprimer (modération)')),
              ],
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (annonce.isPinned) ...[
                const StatusBadge(label: 'ÉPINGLÉ', background: Color(0xFFFFF7ED), foreground: AppColors.accent2),
                const SizedBox(width: 6),
              ],
              StatusBadge.info(annonce.category.toUpperCase()),
              if (annonce.isUrgent) ...[
                const SizedBox(width: 6),
                StatusBadge.danger('URGENT'),
              ],
            ]),
            const SizedBox(height: 12),
            Text(annonce.title, style: Theme.of(context).textTheme.displayMedium),
            const SizedBox(height: 8),
            Text(
              '${annonce.authorName} · ${DateFormat('d MMM yyyy à HH:mm', 'fr_FR').format(annonce.createdAt)}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            Text(annonce.content, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6)),
          ],
        ),
      ),
    );
  }
}
