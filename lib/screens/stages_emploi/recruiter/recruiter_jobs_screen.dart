import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/layout.dart';
import '../../../models/job_offer_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/stages/job_card.dart';
import '../../../widgets/stages/ui.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/stat_tile.dart';
import 'job_form_screen.dart';
import 'job_manage_screen.dart';

class RecruiterJobsScreen extends StatelessWidget {
  const RecruiterJobsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser!;
    return TabPage(
      title: 'Mes offres',
      actions: [
        AddButton(
          key: const ValueKey('job-add'),
          tooltip: 'Publier une offre',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const JobFormScreen())),
        ),
      ],
      children: [
        DbBuilder<List<JobOfferModel>>(
          load: (s) => s.jobs.byRecruiter(user.id),
          builder: (context, jobs) {
            if (jobs.isEmpty) {
              return const EmptyState(
                icon: Icons.work_outline_rounded,
                title: 'Aucune offre publiée',
                subtitle: 'Touchez + pour publier votre premier stage ou emploi.',
              );
            }
            final applicants = jobs.fold<int>(0, (sum, j) => sum + j.applicantCount);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: StatTile(value: '${jobs.where((j) => j.acceptsApplications).length}', label: 'Ouvertes')),
                    const SizedBox(width: kCardGap),
                    Expanded(child: StatTile(value: '$applicants', label: 'Candidats')),
                  ],
                ),
                const SizedBox(height: 16),
                for (final job in jobs)
                  JobCard(
                    key: ValueKey('job-${job.id}'),
                    job: job,
                    showApplicants: true,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => JobManageScreen(jobId: job.id))),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
