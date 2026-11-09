import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/job_offer_model.dart';
import '../../../services/stages/stage_services.dart';
import '../../../widgets/stages/job_card.dart';
import '../../../widgets/stages/ui.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/pill_button.dart';
import '../student/job_detail_screen.dart';
import 'application_review_screen.dart';
import 'job_form_screen.dart';

/// Détail d'une offre côté recruteur : candidats, modification, fermeture.
class JobManageScreen extends StatelessWidget {
  const JobManageScreen({super.key, required this.jobId});

  final String jobId;

  Future<void> _delete(BuildContext context, JobOfferModel job) async {
    final services = context.read<StageServices>();
    final navigator = Navigator.of(context);
    final ok = await confirmAction(
      context,
      title: 'Supprimer cette offre ?',
      message: 'Ses ${job.applicantCount} candidature(s) seront aussi supprimées.',
      confirmLabel: 'Supprimer',
    );
    if (!ok) return;
    await services.jobs.delete(job.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return DbBuilder<(JobOfferModel?, List<ApplicationModel>)>(
      fullScreen: true,
      load: (s) async => (await s.jobs.byId(jobId), await s.applications.byJob(jobId)),
      builder: (context, data) {
        final (job, applications) = data;
        if (job == null) return const DetailPage(title: 'Offre', children: [SizedBox.shrink()]);
        return DetailPage(
          title: 'Offre',
          actions: [
            IconButton(
              key: const ValueKey('job-edit'),
              tooltip: 'Modifier',
              icon: const Icon(Icons.edit_rounded),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => JobFormScreen(job: job))),
            ),
            IconButton(
              key: const ValueKey('job-delete'),
              tooltip: 'Supprimer',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _delete(context, job),
            ),
          ],
          bottom: PillButton(
            key: const ValueKey('job-toggle'),
            label: job.isOpen ? 'Fermer l\'offre' : 'Rouvrir l\'offre',
            style: PillStyle.ghost,
            onPressed: () => context.read<StageServices>().jobs.setOpen(job.id, !job.isOpen),
          ),
          children: [
            JobDescription(job: job),
            SectionTitle('Candidats (${applications.length})'),
            if (applications.isEmpty)
              const EmptyState(
                icon: Icons.people_outline_rounded,
                title: 'Pas encore de candidat',
                subtitle: 'Les candidatures apparaîtront ici.',
              )
            else
              for (final a in applications)
                ApplicationCard(
                  application: a,
                  title: a.studentName,
                  subtitle: a.studentEmail,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ApplicationReviewScreen(applicationId: a.id)),
                  ),
                ),
          ],
        );
      },
    );
  }
}
