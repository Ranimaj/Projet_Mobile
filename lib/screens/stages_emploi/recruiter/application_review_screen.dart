import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../models/job_offer_model.dart';
import '../../../models/stage_records.dart';
import '../../../models/user_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/stages/stage_services.dart';
import '../../../widgets/stages/status_widgets.dart';
import '../../../widgets/stages/ui.dart';
import '../../../widgets/auth/auth_text_field.dart';
import '../../../widgets/initials_avatar.dart';
import '../../../widgets/pill_button.dart';
import '../../../widgets/status_chip.dart';
import '../student/application_detail_screen.dart';

class _Review {
  const _Review(this.application, this.events, this.skills, this.student);

  final ApplicationModel? application;
  final List<ApplicationEvent> events;
  final List<String> skills;
  final AppUser? student;
}

/// Dossier d'un candidat et passage aux étapes suivantes.
class ApplicationReviewScreen extends StatelessWidget {
  const ApplicationReviewScreen({super.key, required this.applicationId});

  final String applicationId;

  Future<void> _openCv(BuildContext context, ApplicationModel a) async {
    if (!File((a.cvUrl ?? '')).existsSync()) {
      showError(context, 'Le fichier du CV est introuvable.');
      return;
    }
    final result = await OpenFilex.open((a.cvUrl ?? ''));
    if (result.type != ResultType.done && context.mounted) {
      showError(context, 'Aucune application disponible pour ouvrir ce fichier.');
    }
  }

  Future<void> _move(BuildContext context, ApplicationModel a, ApplicationStatus target) async {
    final note = await showFormSheet<String>(context, builder: (_) => _MoveSheet(target: target));
    if (note == null || !context.mounted) return;
    final services = context.read<StageServices>();
    final recruiterId = context.read<AuthProvider>().currentUser!.id;
    try {
      final email = await services.applications.moveTo(a.id, target, recruiterId: recruiterId, note: note);
      if (!context.mounted) return;
      switch (email) {
        case EmailStatus.sent:
          showSuccess(context, 'Étape mise à jour, email envoyé au candidat.');
        case EmailStatus.skipped:
          showSuccess(context, 'Étape mise à jour (compte de démonstration : pas d\'email réel).');
        case EmailStatus.pending:
          showError(context, 'Étape mise à jour. Email en attente : SMTP non configuré.');
        case EmailStatus.failed:
          showError(context, 'Étape mise à jour. L\'envoi de l\'email a échoué, il sera réessayé.');
      }
    } on Exception catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return DbBuilder<_Review>(
      fullScreen: true,
      load: (s) async {
        final a = await s.applications.byId(applicationId);
        if (a == null) return const _Review(null, [], [], null);
        final student = s.userById(a.candidateId);
        return _Review(a, a.history, student?.skills ?? const [], student);
      },
      builder: (context, r) {
        final a = r.application;
        if (a == null) return const DetailPage(title: 'Candidature', children: [SizedBox.shrink()]);
        final next = a.status.next;
        return DetailPage(
          title: 'Candidature',
          bottom: a.status.isFinal
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PillButton(
                      key: const ValueKey('status-next'),
                      label: next!.actionLabel,
                      onPressed: () => _move(context, a, next),
                    ),
                    const SizedBox(height: 8),
                    PillButton(
                      key: const ValueKey('status-reject'),
                      label: ApplicationStatus.rejected.actionLabel,
                      style: PillStyle.danger,
                      onPressed: () => _move(context, a, ApplicationStatus.rejected),
                    ),
                  ],
                ),
          children: [
            AppCard(
              child: Row(
                children: [
                  InitialsAvatar(initials: r.student?.initials ?? '?', size: 52),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.studentName, style: text.titleSmall),
                        Text(a.studentEmail, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall),
                        Text(a.jobTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Align(alignment: Alignment.centerLeft, child: ApplicationStatusChip(a.status)),
            const SectionTitle('Suivi'),
            ApplicationTimeline(status: a.status, events: r.events),
            if (r.skills.isNotEmpty) ...[
              const SectionTitle('Compétences'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in r.skills) StatusChip(label: s, style: StatusChipStyle.neutral),
                ],
              ),
            ],
            const SectionTitle('Dossier'),
            ApplicationDossier(application: a, onOpenCv: () => _openCv(context, a)),
          ],
        );
      },
    );
  }
}

class _MoveSheet extends StatefulWidget {
  const _MoveSheet({required this.target});

  final ApplicationStatus target;

  @override
  State<_MoveSheet> createState() => _MoveSheetState();
}

class _MoveSheetState extends State<_MoveSheet> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final rejected = widget.target == ApplicationStatus.rejected;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.target.actionLabel, style: text.titleMedium),
        const SizedBox(height: 4),
        Text('Le candidat recevra un email à cette étape.', style: text.bodyMedium?.copyWith(color: t.textSecondary)),
        const SizedBox(height: 16),
        AuthTextField(
          key: const ValueKey('status-note'),
          label: 'Message au candidat (facultatif)',
          hint: rejected ? 'Un mot d\'explication…' : 'Date, heure, lieu de l\'entretien…',
          icon: Icons.chat_bubble_outline_rounded,
          controller: _note,
          minLines: 3,
          maxLines: 6,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 20),
        PillButton(
          key: const ValueKey('status-confirm'),
          label: 'Confirmer',
          style: rejected ? PillStyle.danger : PillStyle.primary,
          onPressed: () => Navigator.pop(context, _note.text),
        ),
      ],
    );
  }
}
