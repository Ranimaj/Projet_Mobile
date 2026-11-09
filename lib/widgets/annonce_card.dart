import 'package:flutter/material.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/date_format_fr.dart';
import '../models/annonce_model.dart';
import 'status_chip.dart';

/// Carte d'une annonce dans le fil : pastilles (épinglée / catégorie / urgente /
/// en attente de synchro), aperçu du contenu et ciblage.
/// Les annonces officielles ont un fond orangé doux ([AppTokens.primarySoft]).
class AnnonceCard extends StatelessWidget {
  final AnnonceModel annonce;
  final VoidCallback onTap;

  const AnnonceCard({super.key, required this.annonce, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = annonce;
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Semantics(
      button: true,
      label: '${a.category}${a.isUrgent ? ', urgent' : ''} : ${a.title}',
      child: Container(
        decoration: BoxDecoration(
          color: a.isOfficial ? t.primarySoft : t.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: a.isOfficial ? t.primary.withValues(alpha: 0.28) : t.outline,
          ),
          boxShadow: dark ? null : t.cardShadow,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (a.isPinned)
                        const StatusChip(
                            label: 'Épinglée', icon: Icons.push_pin_rounded),
                      StatusChip(
                        label: a.category,
                        style: a.isOfficial
                            ? StatusChipStyle.soft
                            : StatusChipStyle.neutral,
                      ),
                      if (a.isUrgent)
                        const StatusChip(
                            label: 'Urgent',
                            style: StatusChipStyle.danger,
                            icon: Icons.priority_high_rounded),
                      if (a.pendingSync)
                        const StatusChip(
                            label: 'En attente de synchro',
                            style: StatusChipStyle.warning,
                            icon: Icons.sync_rounded),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(a.title, style: text.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    a.content,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${a.authorName} · ${relativeDateFr(a.createdAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall,
                        ),
                      ),
                      if (a.isTargeted) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.groups_rounded, size: 16, color: t.primary),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            a.targetLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall!.copyWith(
                                color: t.onPrimarySoft,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
