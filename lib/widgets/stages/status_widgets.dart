import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../../models/job_offer_model.dart';
import '../../models/stage_records.dart';
import '../status_chip.dart';
import 'ui.dart';

class ApplicationStatusChip extends StatelessWidget {
  const ApplicationStatusChip(this.status, {super.key});

  final ApplicationStatus status;

  @override
  Widget build(BuildContext context) {
    final (style, icon) = switch (status) {
      ApplicationStatus.pending => (StatusChipStyle.neutral, Icons.hourglass_top_rounded),
      ApplicationStatus.hrInterview => (StatusChipStyle.soft, Icons.groups_rounded),
      ApplicationStatus.technicalInterview => (StatusChipStyle.warning, Icons.code_rounded),
      ApplicationStatus.accepted => (StatusChipStyle.success, Icons.check_circle_rounded),
      ApplicationStatus.rejected => (StatusChipStyle.danger, Icons.cancel_rounded),
    };
    return StatusChip(label: status.label, style: style, icon: icon);
  }
}

/// Progression compacte : un segment par étape du parcours.
class StatusProgress extends StatelessWidget {
  const StatusProgress(this.status, {super.key});

  final ApplicationStatus status;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final reached = ApplicationStatus.pipeline.indexOf(status);
    final rejected = status == ApplicationStatus.rejected;
    return Row(
      children: [
        for (var i = 0; i < ApplicationStatus.pipeline.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: rejected ? t.dangerSoft : (i <= reached ? t.primary : t.surfaceMuted),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Frise du suivi, identique pour le recruteur et l'étudiant.
class ApplicationTimeline extends StatelessWidget {
  const ApplicationTimeline({super.key, required this.status, required this.events});

  final ApplicationStatus status;
  final List<ApplicationEvent> events;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final byStatus = {for (final e in events) e.status: e};
    final steps = status == ApplicationStatus.rejected
        ? [...ApplicationStatus.pipeline.where(byStatus.containsKey), ApplicationStatus.rejected]
        : ApplicationStatus.pipeline;

    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 28,
                  child: Column(
                    children: [
                      _Dot(done: byStatus.containsKey(steps[i]), danger: steps[i] == ApplicationStatus.rejected),
                      if (i < steps.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            color: byStatus.containsKey(steps[i + 1]) ? t.primary : t.outline,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          steps[i].label,
                          style: text.titleSmall?.copyWith(
                            color: byStatus.containsKey(steps[i]) ? t.textPrimary : t.textSecondary,
                          ),
                        ),
                        if (byStatus[steps[i]] case final event?) ...[
                          const SizedBox(height: 2),
                          Text(formatDateTime(event.createdAt), style: text.bodySmall),
                          if (event.note.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(event.note, style: text.bodyMedium?.copyWith(color: t.textPrimary)),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.done, required this.danger});

  final bool done;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final color = danger ? t.danger : t.primary;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(color: done ? color : t.surfaceMuted, shape: BoxShape.circle),
      child: done ? Icon(danger ? Icons.close_rounded : Icons.check_rounded, size: 16, color: t.onPrimary) : null,
    );
  }
}

/// Pastille de compatibilité sur les cartes d'offres.
class MatchBadge extends StatelessWidget {
  const MatchBadge(this.match, {super.key});

  final MatchScore match;

  @override
  Widget build(BuildContext context) {
    return StatusChip(
      label: match.isAi ? '${match.score}% match' : '${match.score}% estimé',
      style: match.score >= 70 ? StatusChipStyle.success : (match.score >= 40 ? StatusChipStyle.warning : StatusChipStyle.neutral),
      icon: match.isAi ? Icons.auto_awesome_rounded : Icons.calculate_outlined,
    );
  }
}

/// Carte détaillée du score sur la fiche d'une offre.
class MatchCard extends StatelessWidget {
  const MatchCard(this.match, {super.key});

  final MatchScore match;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    return AppCard(
      child: Row(
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: match.score / 100,
                    strokeWidth: 6,
                    color: t.primary,
                    backgroundColor: t.surfaceMuted,
                  ),
                ),
                Text('${match.score}%', style: text.titleSmall),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(match.isAi ? 'Compatibilité calculée par Gemini' : 'Estimation selon vos compétences', style: text.titleSmall),
                const SizedBox(height: 4),
                Text(match.reason, style: text.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
