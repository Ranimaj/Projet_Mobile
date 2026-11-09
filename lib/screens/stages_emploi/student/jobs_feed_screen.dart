import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/job_offer_model.dart';
import '../../../models/stage_records.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/stages/job_card.dart';
import '../../../widgets/stages/ui.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/filter_chip_pill.dart';
import 'job_detail_screen.dart';

class _Feed {
  const _Feed(this.jobs, this.scores, this.applied);

  final List<JobOfferModel> jobs;
  final Map<String, MatchScore> scores;
  final Set<String> applied;
}

class JobsFeedScreen extends StatefulWidget {
  const JobsFeedScreen({super.key});

  @override
  State<JobsFeedScreen> createState() => _JobsFeedScreenState();
}

class _JobsFeedScreenState extends State<JobsFeedScreen> {
  String _query = '';
  JobType? _type;
  bool _bestFirst = true;

  List<JobOfferModel> _visible(_Feed feed) {
    final q = _query.trim().toLowerCase();
    final list = feed.jobs.where((j) {
      if (_type != null && j.type != _type) return false;
      if (q.isEmpty) return true;
      return '${j.title} ${j.companyName} ${j.location} ${j.requiredSkills.join(' ')}'.toLowerCase().contains(q);
    }).toList();
    if (_bestFirst) {
      list.sort((a, b) => (feed.scores[b.id]?.score ?? 0).compareTo(feed.scores[a.id]?.score ?? 0));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser!;
    return TabPage(
      title: 'Offres',
      subtitle: 'Bonjour ${user.fullName.split(' ').first}',
      children: [
        SearchField(hint: 'Poste, entreprise, compétence…', onChanged: (v) => setState(() => _query = v)),
        const SizedBox(height: 8),
        FilterRow(
          children: [
            FilterChipPill(
              label: 'Meilleur match',
              icon: Icons.auto_awesome_rounded,
              selected: _bestFirst,
              onTap: () => setState(() => _bestFirst = !_bestFirst),
            ),
            FilterChipPill(label: 'Tout', selected: _type == null, onTap: () => setState(() => _type = null)),
            for (final type in JobType.values)
              FilterChipPill(label: type.label, selected: _type == type, onTap: () => setState(() => _type = type)),
          ],
        ),
        const SizedBox(height: 8),
        DbBuilder<_Feed>(
          // Le score dépend du profil : on relit dès qu'il change.
          key: ValueKey('${user.skills.join(',')}|${user.major}|${user.year}'),
          load: (s) async {
            final jobs = await s.jobs.open();
            unawaited(s.matching.refresh(user, jobs));
            return _Feed(jobs, await s.matching.scores(user, jobs), await s.applications.appliedJobIds(user.id));
          },
          builder: (context, feed) {
            final jobs = _visible(feed);
            if (jobs.isEmpty) {
              return const EmptyState(
                icon: Icons.search_off_rounded,
                title: 'Aucune offre',
                subtitle: 'Modifiez vos filtres ou revenez bientôt.',
              );
            }
            return Column(
              children: [
                for (final job in jobs)
                  JobCard(
                    key: ValueKey('job-${job.id}'),
                    job: job,
                    match: feed.scores[job.id],
                    applied: feed.applied.contains(job.id),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => JobDetailScreen(jobId: job.id))),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
