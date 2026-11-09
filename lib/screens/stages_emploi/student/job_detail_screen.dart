import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/job_offer_model.dart';
import '../../../models/stage_records.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/stages/job_card.dart';
import '../../../widgets/stages/status_widgets.dart';
import '../../../widgets/stages/ui.dart';
import '../../../widgets/pill_button.dart';
import '../../../widgets/status_chip.dart';
import 'application_detail_screen.dart';
import '../../../widgets/stages/recruiter_trust.dart';
import 'apply_flow_screen.dart';

class _Detail {
  const _Detail(this.job, this.match, this.application, this.skills);

  final JobOfferModel? job;
  final MatchScore? match;
  final ApplicationModel? application;
  final Set<String> skills;
}

class JobDetailScreen extends StatelessWidget {
  const JobDetailScreen({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context) {
    final user = context.read<AuthProvider>().currentUser!;
    return DbBuilder<_Detail>(
      fullScreen: true,
      load: (s) async {
        final job = await s.jobs.byId(jobId);
        if (job == null) return const _Detail(null, null, null, {});
        final applications = await s.applications.byStudent(user.id);
        return _Detail(
          job,
          (await s.matching.scores(user, [job]))[job.id],
          applications.where((a) => a.jobOfferId == jobId).firstOrNull,
          user.skills.map((e) => e.toLowerCase()).toSet(),
        );
      },
      builder: (context, d) {
        final job = d.job;
        if (job == null) {
          return const DetailPage(title: 'Offre', children: [Text('Cette offre n\'existe plus.')]);
        }
        return DetailPage(
          title: job.type.label,
          bottom: _bottom(context, job, d.application),
          children: [RecruiterTrust(recruiterId: job.recruiterId), JobDescription(job: job, match: d.match, ownedSkills: d.skills)],
        );
      },
    );
  }

  Widget _bottom(BuildContext context, JobOfferModel job, ApplicationModel? application) {
    if (application != null) {
      return PillButton(
        label: 'Voir ma candidature',
        style: PillStyle.ghost,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ApplicationDetailScreen(applicationId: application.id)),
        ),
      );
    }
    if (!job.acceptsApplications) return const PillButton(label: 'Offre fermée', onPressed: null);
    return PillButton(
      key: const ValueKey('apply-start'),
      label: 'Postuler',
      icon: Icons.send_rounded,
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ApplyFlowScreen(jobId: job.id, jobTitle: job.title, company: job.companyName)),
      ),
    );
  }
}

/// Contenu d'une offre, partagé entre l'étudiant et le recruteur.
class JobDescription extends StatelessWidget {
  const JobDescription({super.key, required this.job, this.match, this.ownedSkills = const {}});

  final JobOfferModel job;
  final MatchScore? match;
  final Set<String> ownedSkills;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final deadline = job.deadline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            CompanyTile(job.companyName),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(job.title, style: text.headlineMedium),
                  Text('${job.companyName} · ${job.location}', style: text.bodyMedium),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            StatusChip(label: job.type.label),
            if (job.duration.isNotEmpty) StatusChip(label: job.duration, style: StatusChipStyle.neutral),
            if (deadline != null) StatusChip(label: 'Jusqu\'au ${formatDate(deadline)}', style: StatusChipStyle.neutral),
          ],
        ),
        const SizedBox(height: 16),
        if (match != null) MatchCard(match!),
        const SectionTitle('Description'),
        Text(job.description, style: text.bodyLarge),
        if (job.requirements.isNotEmpty) ...[
          const SectionTitle('Prérequis'),
          Text(job.requirements, style: text.bodyLarge),
        ],
        if (job.requiredSkills.isNotEmpty) ...[
          const SectionTitle('Compétences recherchées'),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final skill in job.requiredSkills)
                ownedSkills.contains(skill.toLowerCase())
                    ? StatusChip(label: skill, style: StatusChipStyle.success, icon: Icons.check_rounded)
                    : StatusChip(label: skill, style: StatusChipStyle.neutral),
            ],
          ),
        ],
      ],
    );
  }
}
