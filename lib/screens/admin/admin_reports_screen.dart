import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_tokens.dart';
import '../../providers/auth_provider.dart';
import '../../core/utils/fr_dates.dart';
import '../../services/report_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_chip.dart';

/// Administration — signalements à traiter. « Confirmer » retire des points
/// de confiance au compte signalé ; « Rejeter » classe le signalement.
class AdminReportsScreen extends StatefulWidget {
  final ReportService? service;
  const AdminReportsScreen({super.key, this.service});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  late final ReportService _service = widget.service ?? ReportService();
  late final Stream<List<UserReport>> _pending = _service.watchPending();
  final _busy = <String>{};

  Future<void> _decide(UserReport r, {required bool confirm}) async {
    final adminId = context.read<AuthProvider>().currentUser?.id;
    if (adminId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy.add(r.id));
    try {
      if (confirm) {
        await _service.confirm(r, adminId: adminId);
      } else {
        await _service.dismiss(r, adminId: adminId);
      }
      messenger.showSnackBar(SnackBar(
          content: Text(confirm ? 'Signalement confirmé : ${r.targetName} perd des points.' : 'Signalement rejeté.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Action impossible.')));
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Signalements')),
      body: StreamBuilder<List<UserReport>>(
        stream: _pending,
        builder: (context, snap) {
          if (snap.hasError) return const Center(child: Text('Impossible de charger les signalements.'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final reports = snap.data!;
          if (reports.isEmpty) {
            return const EmptyState(
              icon: Icons.verified_user_rounded,
              title: 'Aucun signalement',
              subtitle: 'Tout est calme pour le moment.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: reports.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final r = reports[i];
              final busy = _busy.contains(r.id);
              return Container(
                key: Key('report-${r.id}'),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: t.cardShadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Le motif passe à la ligne sur un écran étroit.
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(r.targetName, style: text.titleMedium),
                        StatusChip(label: r.reason.label, style: StatusChipStyle.danger),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Signalé par ${r.reporterName} · ${FrDates.shortDateTime(r.createdAt)}',
                        style: text.labelMedium?.copyWith(color: t.textSecondary)),
                    if (r.details.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(r.details, style: text.bodyMedium),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          key: Key('dismiss-${r.id}'),
                          onPressed: busy ? null : () => _decide(r, confirm: false),
                          child: const Text('Rejeter'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          key: Key('confirm-${r.id}'),
                          style: FilledButton.styleFrom(backgroundColor: t.danger),
                          onPressed: busy ? null : () => _decide(r, confirm: true),
                          child: const Text('Confirmer'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
