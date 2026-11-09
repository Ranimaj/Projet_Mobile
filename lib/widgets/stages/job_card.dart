import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../../models/job_offer_model.dart';
import '../../models/stage_records.dart';
import '../status_chip.dart';
import 'status_widgets.dart';
import 'ui.dart';

class CompanyTile extends StatelessWidget {
  const CompanyTile(this.company, {super.key});

  final String company;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: t.primarySoft, borderRadius: BorderRadius.circular(14)),
      child: Text(
        company.trim().isEmpty ? '?' : company.trim()[0].toUpperCase(),
        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: t.onPrimarySoft),
      ),
    );
  }
}

class JobCard extends StatelessWidget {
  const JobCard({super.key, required this.job, this.match, this.applied = false, this.showApplicants = false, this.onTap});

  final JobOfferModel job;
  final MatchScore? match;
  final bool applied;
  final bool showApplicants;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final deadline = job.deadline;
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CompanyTile(job.companyName),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(job.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                    const SizedBox(height: 2),
                    Text('${job.companyName} · ${job.location}', maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall),
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
              if (match != null) MatchBadge(match!),
              StatusChip(label: job.type.label),
              if (job.duration.isNotEmpty) StatusChip(label: job.duration, style: StatusChipStyle.neutral),
              if (applied) const StatusChip(label: 'Déjà postulé', style: StatusChipStyle.success, icon: Icons.check_rounded),
              if (showApplicants)
                StatusChip(
                  label: '${job.applicantCount} candidat${job.applicantCount > 1 ? 's' : ''}',
                  style: StatusChipStyle.neutral,
                  icon: Icons.people_alt_rounded,
                ),
              if (!job.acceptsApplications)
                const StatusChip(label: 'Fermée', style: StatusChipStyle.danger)
              else if (deadline != null)
                StatusChip(label: 'Jusqu\'au ${formatDate(deadline)}', style: StatusChipStyle.neutral),
            ],
          ),
        ],
      ),
    );
  }
}

class ApplicationCard extends StatelessWidget {
  const ApplicationCard({super.key, required this.application, required this.title, required this.subtitle, this.onTap});

  final ApplicationModel application;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleSmall),
          const SizedBox(height: 2),
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: t.textSecondary)),
          const SizedBox(height: 12),
          StatusProgress(application.status),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ApplicationStatusChip(application.status),
              Text('Mise à jour le ${formatDate(application.updatedAt)}', style: text.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}
