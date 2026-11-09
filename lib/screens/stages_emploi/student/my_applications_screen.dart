import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/job_offer_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../widgets/stages/job_card.dart';
import '../../../widgets/stages/ui.dart';
import '../../../widgets/empty_state.dart';
import 'application_detail_screen.dart';

class MyApplicationsScreen extends StatelessWidget {
  const MyApplicationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser!;
    return TabPage(
      title: 'Candidatures',
      subtitle: 'Suivez chaque étape',
      children: [
        DbBuilder<List<ApplicationModel>>(
          load: (s) => s.applications.byStudent(user.id),
          builder: (context, list) {
            if (list.isEmpty) {
              return const EmptyState(
                icon: Icons.assignment_outlined,
                title: 'Aucune candidature',
                subtitle: 'Postulez à une offre pour suivre son avancement ici.',
              );
            }
            return Column(
              children: [
                for (final a in list)
                  ApplicationCard(
                    key: ValueKey('application-${a.id}'),
                    application: a,
                    title: a.jobTitle,
                    subtitle: a.companyName,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ApplicationDetailScreen(applicationId: a.id)),
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
