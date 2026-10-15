import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/job_offer_model.dart';
import '../../providers/job_provider.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_badge.dart';

/// Suivi en temps réel du statut des candidatures (fonctionnalité avancée) :
/// Envoyée → Vue → Acceptée/Refusée.
class MyApplicationsScreen extends StatelessWidget {
  const MyApplicationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final applications = context.watch<JobProvider>().myApplications;

    return Scaffold(
      appBar: AppBar(title: const Text('Mes candidatures')),
      body: applications.isEmpty
          ? const EmptyState(
              icon: Icons.assignment_outlined,
              title: 'Aucune candidature envoyée',
              subtitle: "Postulez à une offre pour suivre son statut ici en temps réel.",
            )
          : ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: applications.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final app = applications[i];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(app.jobTitle,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                          ),
                          _statusBadge(app.status),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(app.companyName, style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 8),
                      Text('Envoyée le ${DateFormat('d MMM yyyy', 'fr_FR').format(app.appliedAt)}',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11.5)),
                      if (app.pendingSync) ...[
                        const SizedBox(height: 6),
                        StatusBadge.warning('En attente de synchro'),
                      ],
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _statusBadge(ApplicationStatus status) {
    switch (status) {
      case ApplicationStatus.sent:
        return StatusBadge.info('Envoyée');
      case ApplicationStatus.seen:
        return StatusBadge.warning('Vue');
      case ApplicationStatus.accepted:
        return StatusBadge.success('Acceptée');
      case ApplicationStatus.rejected:
        return StatusBadge.danger('Refusée');
    }
  }
}
