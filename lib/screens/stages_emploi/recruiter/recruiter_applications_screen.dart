import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/job_offer_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/stages/job_card.dart';
import '../../../widgets/stages/ui.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/filter_chip_pill.dart';
import 'application_review_screen.dart';

class RecruiterApplicationsScreen extends StatefulWidget {
  const RecruiterApplicationsScreen({super.key});

  @override
  State<RecruiterApplicationsScreen> createState() => _RecruiterApplicationsScreenState();
}

class _RecruiterApplicationsScreenState extends State<RecruiterApplicationsScreen> {
  ApplicationStatus? _filter;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser!;
    return TabPage(
      title: 'Candidats',
      subtitle: 'Suivi des candidatures',
      children: [
        SearchField(hint: 'Nom du candidat ou offre…', onChanged: (v) => setState(() => _query = v)),
        const SizedBox(height: 8),
        FilterRow(
          children: [
            FilterChipPill(label: 'Tous', selected: _filter == null, onTap: () => setState(() => _filter = null)),
            for (final status in ApplicationStatus.values)
              FilterChipPill(label: status.label, selected: _filter == status, onTap: () => setState(() => _filter = status)),
          ],
        ),
        const SizedBox(height: 8),
        DbBuilder<List<ApplicationModel>>(
          load: (s) => s.applications.byRecruiter(user.id),
          builder: (context, list) {
            final q = _query.trim().toLowerCase();
            final visible = list.where((a) {
              if (_filter != null && a.status != _filter) return false;
              return q.isEmpty || '${a.studentName} ${a.jobTitle}'.toLowerCase().contains(q);
            }).toList();
            if (visible.isEmpty) {
              return const EmptyState(
                icon: Icons.people_outline_rounded,
                title: 'Aucun candidat',
                subtitle: 'Rien ne correspond pour le moment.',
              );
            }
            return Column(
              children: [
                for (final a in visible)
                  ApplicationCard(
                    key: ValueKey('candidate-${a.id}'),
                    application: a,
                    title: a.studentName,
                    subtitle: a.jobTitle,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ApplicationReviewScreen(applicationId: a.id)),
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
