import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/job_offer_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/stages/stage_services.dart';
import '../../../widgets/stages/status_widgets.dart';
import '../../../widgets/stages/ui.dart';
import '../../../widgets/pill_button.dart';
import 'apply_flow_screen.dart';

class ApplicationDetailScreen extends StatelessWidget {
  const ApplicationDetailScreen({super.key, required this.applicationId});

  final String applicationId;

  Future<void> _withdraw(BuildContext context, ApplicationModel a) async {
    final services = context.read<StageServices>();
    final studentId = context.read<AuthProvider>().currentUser!.id;
    final navigator = Navigator.of(context);
    final ok = await confirmAction(
      context,
      title: 'Retirer la candidature ?',
      message: 'Votre CV, votre lettre et votre message seront supprimés.',
      confirmLabel: 'Retirer',
    );
    if (!ok) return;
    try {
      await services.applications.withdraw(a.id, studentId);
      navigator.pop();
    } on Exception catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return DbBuilder<(ApplicationModel?, List<ApplicationEvent>)>(
      fullScreen: true,
      load: (s) async => (await s.applications.byId(applicationId), await s.applications.events(applicationId)),
      builder: (context, data) {
        final (a, events) = data;
        if (a == null) return const DetailPage(title: 'Candidature', children: [SizedBox.shrink()]);
        final editable = a.status == ApplicationStatus.pending;
        return DetailPage(
          title: 'Ma candidature',
          bottom: editable
              ? Row(
                  children: [
                    Expanded(child: PillButton(label: 'Retirer', style: PillStyle.danger, onPressed: () => _withdraw(context, a))),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PillButton(
                        label: 'Modifier',
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ApplyFlowScreen(jobId: a.jobOfferId, jobTitle: a.jobTitle, company: a.companyName, existing: a),
                        )),
                      ),
                    ),
                  ],
                )
              : null,
          children: [
            Text(a.jobTitle, style: text.headlineMedium),
            Text(a.companyName, style: text.bodyMedium),
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: ApplicationStatusChip(a.status)),
            const SectionTitle('Suivi'),
            ApplicationTimeline(status: a.status, events: events),
            const SectionTitle('Mon dossier'),
            ApplicationDossier(application: a),
          ],
        );
      },
    );
  }
}

/// CV, lettre et message d'une candidature.
class ApplicationDossier extends StatelessWidget {
  const ApplicationDossier({super.key, required this.application, this.onOpenCv});

  final ApplicationModel application;
  final VoidCallback? onOpenCv;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget block(String title, String body) => AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: text.labelLarge),
              const SizedBox(height: 6),
              Text(body, style: text.bodyMedium),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          onTap: onOpenCv,
          child: Row(
            children: [
              const Icon(Icons.description_rounded),
              const SizedBox(width: 12),
              Expanded(child: Text(application.cvName, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleSmall)),
              if (onOpenCv != null) const Icon(Icons.open_in_new_rounded, size: 20),
            ],
          ),
        ),
        block('Lettre de motivation', (application.coverLetter ?? '')),
        block('Message au recruteur', application.message),
      ],
    );
  }
}
