import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_tokens.dart';
import '../../providers/annonce_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/annonce_location_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/translatable_text.dart';
import 'add_annonce_screen.dart';

/// Détail d'une annonce + actions selon les droits :
/// modifier (auteur / admin), supprimer (auteur / admin), épingler (admin).
/// L'écran relit l'annonce dans le provider (par id) pour toujours afficher
/// la version à jour après une modification.
class AnnonceDetailScreen extends StatelessWidget {
  final String annonceId;
  const AnnonceDetailScreen({super.key, required this.annonceId});

  Future<void> _confirmDelete(BuildContext context, AnnonceProvider provider) async {
    final danger = AppTokens.of(context).danger;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette annonce ?'),
        content: const Text('Cette action est définitive.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Supprimer', style: TextStyle(color: danger)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    await provider.deleteAnnonce(annonceId);
    messenger.showSnackBar(const SnackBar(content: Text('Annonce supprimée.')));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final provider = context.watch<AnnonceProvider>();
    context.watch<AuthProvider>(); // rebuild si le profil change
    final annonce = provider.byId(annonceId);
    final fmt = DateFormat('d MMM yyyy à HH:mm', 'fr_FR');

    if (annonce == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Annonce')),
        body: const EmptyState(
          icon: Icons.campaign_outlined,
          title: 'Annonce introuvable',
          subtitle: "Elle a peut-être été supprimée.",
        ),
      );
    }

    final canEdit = provider.canEdit(annonce);
    final canPin = provider.canPin(annonce);
    final canDelete = provider.canDelete(annonce);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Annonce'),
        actions: [
          if (canEdit || canPin || canDelete)
            PopupMenuButton<String>(
              tooltip: 'Actions',
              onSelected: (value) async {
                switch (value) {
                  case 'edit':
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => AddAnnonceScreen(annonce: annonce),
                    ));
                    break;
                  case 'pin':
                    await provider.pinAnnonce(annonce.id, !annonce.isPinned);
                    break;
                  case 'delete':
                    await _confirmDelete(context, provider);
                    break;
                }
              },
              itemBuilder: (_) => [
                if (canEdit) const PopupMenuItem(value: 'edit', child: Text('Modifier')),
                if (canPin)
                  PopupMenuItem(
                      value: 'pin', child: Text(annonce.isPinned ? 'Désépingler' : 'Épingler')),
                if (canDelete) const PopupMenuItem(value: 'delete', child: Text('Supprimer')),
              ],
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (annonce.pendingSync)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.warningSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Icon(Icons.sync_rounded, size: 18, color: t.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'En attente de synchronisation — sera envoyée au retour du réseau.',
                      style: text.labelMedium!.copyWith(color: t.warning),
                    ),
                  ),
                ]),
              ),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (annonce.isPinned)
                const StatusChip(label: 'Épinglée', icon: Icons.push_pin_rounded),
              StatusChip(
                label: annonce.category,
                style: annonce.isOfficial ? StatusChipStyle.soft : StatusChipStyle.neutral,
              ),
              if (annonce.isUrgent)
                const StatusChip(
                    label: 'Urgent',
                    style: StatusChipStyle.danger,
                    icon: Icons.priority_high_rounded),
            ]),
            const SizedBox(height: 14),
            Text(annonce.title, style: text.displayMedium),
            const SizedBox(height: 8),
            Text(
              '${annonce.authorName} · ${fmt.format(annonce.createdAt)}'
              '${annonce.updatedAt != null ? ' · modifiée le ${DateFormat('d MMM', 'fr_FR').format(annonce.updatedAt!)}' : ''}',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 18),
            TranslatableText(
              text: annonce.content,
              style: text.bodyLarge?.copyWith(height: 1.6),
            ),
            if (annonce.hasLocation) ...[
              const SizedBox(height: 18),
              AnnonceLocationCard(annonce: annonce),
            ],
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.surface,
                border: Border.all(color: t.outline),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                Icon(Icons.groups_rounded, size: 20, color: t.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Destinataires', style: text.bodySmall),
                      const SizedBox(height: 2),
                      Text(annonce.targetLabel, style: text.titleSmall),
                    ],
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
