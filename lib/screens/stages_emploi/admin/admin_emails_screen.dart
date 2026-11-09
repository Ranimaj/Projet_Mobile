import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../models/stage_records.dart';
import '../../../services/stages/stage_services.dart';
import '../../../widgets/stages/ui.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/pill_button.dart';
import '../../../widgets/status_chip.dart';

/// Journal des emails envoyés aux candidats.
class AdminEmailsScreen extends StatelessWidget {
  const AdminEmailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final configured = context.read<StageServices>().emails.isConfigured;
    final text = Theme.of(context).textTheme;
    final t = AppTokens.of(context);
    return DetailPage(
      title: 'Emails',
      children: [
        Text(configured ? 'Envoi par Gmail actif' : 'SMTP non configuré : les emails restent en attente', style: text.bodyMedium),
        const SizedBox(height: 12),
        DbBuilder<List<EmailRecord>>(
          load: (s) => s.emails.all(),
          builder: (context, emails) {
            if (emails.isEmpty) {
              return const EmptyState(icon: Icons.mail_outline_rounded, title: 'Aucun email', subtitle: 'Les emails de suivi apparaîtront ici.');
            }
            return Column(
              children: [
                for (final e in emails)
                  AppCard(
                    onTap: () => showFormSheet(context, builder: (_) => _EmailSheet(email: e)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.subject, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                        const SizedBox(height: 2),
                        Text(e.recipient, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: t.textSecondary)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [_EmailChip(e.status), Text(formatDateTime(e.createdAt), style: text.bodySmall)],
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _EmailChip extends StatelessWidget {
  const _EmailChip(this.status);

  final EmailStatus status;

  @override
  Widget build(BuildContext context) => switch (status) {
        EmailStatus.sent => const StatusChip(label: 'Envoyé', style: StatusChipStyle.success),
        EmailStatus.pending => const StatusChip(label: 'En attente', style: StatusChipStyle.warning),
        EmailStatus.failed => const StatusChip(label: 'Échec', style: StatusChipStyle.danger),
        EmailStatus.skipped => const StatusChip(label: 'Démo', style: StatusChipStyle.neutral),
      };
}

class _EmailSheet extends StatelessWidget {
  const _EmailSheet({required this.email});

  final EmailRecord email;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final services = context.read<StageServices>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(email.subject, style: text.titleMedium),
        const SizedBox(height: 4),
        Text('À : ${email.recipient}', style: text.bodySmall),
        const SizedBox(height: 12),
        Text(email.body, style: text.bodyMedium),
        if (email.error.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(email.error, style: text.bodySmall?.copyWith(color: AppTokens.of(context).danger)),
        ],
        if (email.status != EmailStatus.sent && email.status != EmailStatus.skipped && services.emails.isConfigured) ...[
          const SizedBox(height: 16),
          PillButton(
            label: 'Renvoyer',
            icon: Icons.send_rounded,
            onPressed: () {
              Navigator.pop(context);
              services.emails.retry(email.id);
            },
          ),
        ],
      ],
    );
  }
}
