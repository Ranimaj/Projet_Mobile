import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/layout.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/filter_chip_pill.dart';
import '../../widgets/stages/ui.dart';
import 'admin/admin_jobs_screen.dart';
import 'recruiter/recruiter_applications_screen.dart';
import 'recruiter/recruiter_jobs_screen.dart';
import 'student/candidate_profile_screen.dart';
import 'student/jobs_feed_screen.dart';
import 'student/my_applications_screen.dart';

/// Onglet Stages : l'écran dépend du rôle du compte connecté.
class StagesListScreen extends StatelessWidget {
  const StagesListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final role = context.select<AuthProvider, UserRole?>((a) => a.currentUser?.role);
    return switch (role) {
      null => const Scaffold(
          body: EmptyState(
            icon: Icons.work_rounded,
            title: 'Stage & Emploi',
            subtitle: 'Connectez-vous pour consulter les offres et postuler.',
          ),
        ),
      UserRole.admin => const AdminJobsScreen(),
      UserRole.recruiter => const _Tabs(
          key: ValueKey('stages-recruiter'),
          labels: ['Mes offres', 'Candidats'],
          pages: [RecruiterJobsScreen(), RecruiterApplicationsScreen()],
        ),
      UserRole.student => const _Tabs(
          key: ValueKey('stages-student'),
          labels: ['Offres', 'Candidatures', 'Mon profil'],
          pages: [JobsFeedScreen(), MyApplicationsScreen(), CandidateProfileScreen()],
        ),
    };
  }
}

class _Tabs extends StatefulWidget {
  const _Tabs({super.key, required this.labels, required this.pages});

  final List<String> labels;
  final List<Widget> pages;

  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: ContentWidth(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(kPagePadding, 8, kPagePadding, 0),
                child: FilterRow(
                  children: [
                    for (var i = 0; i < widget.labels.length; i++)
                      FilterChipPill(
                        key: ValueKey('stages-tab-${widget.labels[i]}'),
                        label: widget.labels[i],
                        selected: i == _index,
                        onTap: () => setState(() => _index = i),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: IndexedStack(index: _index, children: widget.pages),
            ),
          ),
        ],
      ),
    );
  }
}
