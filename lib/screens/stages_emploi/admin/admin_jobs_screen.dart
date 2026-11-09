import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/job_offer_model.dart';
import '../../../services/stages/stage_services.dart';
import '../../../widgets/stages/job_card.dart';
import '../../../widgets/stages/ui.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/pill_button.dart';
import '../student/job_detail_screen.dart';

/// Modération des offres par l'administrateur.
class AdminJobsScreen extends StatefulWidget {
  const AdminJobsScreen({super.key});

  @override
  State<AdminJobsScreen> createState() => _AdminJobsScreenState();
}

class _AdminJobsScreenState extends State<AdminJobsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return DetailPage(
      title: 'Offres',
      children: [
        SearchField(hint: 'Poste ou entreprise…', onChanged: (v) => setState(() => _query = v)),
        const SizedBox(height: 12),
        DbBuilder<List<JobOfferModel>>(
          load: (s) => s.jobs.all(),
          builder: (context, jobs) {
            final q = _query.trim().toLowerCase();
            final visible = jobs.where((j) => q.isEmpty || '${j.title} ${j.companyName}'.toLowerCase().contains(q)).toList();
            if (visible.isEmpty) {
              return const EmptyState(icon: Icons.work_outline_rounded, title: 'Aucune offre', subtitle: 'Rien à modérer pour le moment.');
            }
            return Column(
              children: [
                for (final job in visible)
                  JobCard(
                    key: ValueKey('job-${job.id}'),
                    job: job,
                    showApplicants: true,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _AdminJobScreen(jobId: job.id))),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AdminJobScreen extends StatelessWidget {
  const _AdminJobScreen({required this.jobId});

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
    return DbBuilder<JobOfferModel?>(
      fullScreen: true,
      load: (s) => s.jobs.byId(jobId),
      builder: (context, job) {
        if (job == null) return const DetailPage(title: 'Offre', children: [SizedBox.shrink()]);
        return DetailPage(
          title: 'Offre',
          bottom: Row(
            children: [
              Expanded(child: PillButton(label: 'Supprimer', style: PillStyle.danger, onPressed: () => _delete(context, job))),
              const SizedBox(width: 12),
              Expanded(
                child: PillButton(
                  label: job.isOpen ? 'Fermer' : 'Rouvrir',
                  style: PillStyle.ghost,
                  onPressed: () => context.read<StageServices>().jobs.setOpen(job.id, !job.isOpen),
                ),
              ),
            ],
          ),
          children: [JobDescription(job: job)],
        );
      },
    );
  }
}
