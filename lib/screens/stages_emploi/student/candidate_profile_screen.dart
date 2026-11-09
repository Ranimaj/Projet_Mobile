import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/validators.dart';
import '../../../models/stage_records.dart';
import '../../../models/user_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/stages/stage_services.dart';
import '../../../widgets/auth/auth_text_field.dart';
import '../../../widgets/empty_state.dart';
import '../../../widgets/pill_button.dart';
import '../../../widgets/round_icon_button.dart';
import '../../../widgets/stages/ui.dart';

/// Profil de candidature : compétences du compte, formations et expériences.
class CandidateProfileScreen extends StatelessWidget {
  const CandidateProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    if (user == null) return const SizedBox.shrink();
    return TabPage(
      title: 'Mon profil',
      subtitle: 'Utilisé pour calculer votre compatibilité',
      children: [
        _Skills(user),
        SectionTitle(
          'Formations et expériences',
          trailing: RoundIconButton(
            key: const ValueKey('add-experience'),
            icon: Icons.add_rounded,
            tooltip: 'Ajouter une formation ou expérience',
            style: RoundButtonStyle.soft,
            onPressed: () => showFormSheet(context, builder: (_) => _ExperienceForm(userId: user.id)),
          ),
        ),
        DbBuilder<List<Experience>>(
          load: (s) async => s.experiences.forUser(user.id),
          builder: (context, experiences) {
            if (experiences.isEmpty) {
              return const EmptyState(
                icon: Icons.history_edu_rounded,
                title: 'Rien pour le moment',
                subtitle: 'Ajoutez votre cursus et vos expériences.',
              );
            }
            return Column(
              children: [
                for (final e in experiences)
                  AppCard(
                    onTap: () => showFormSheet(context, builder: (_) => _ExperienceForm(userId: user.id, experience: e)),
                    child: _ExperienceRow(e),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Skills extends StatelessWidget {
  const _Skills(this.user);

  final AppUser user;

  Future<void> _remove(BuildContext context, String skill) async {
    final auth = context.read<AuthProvider>();
    final current = auth.currentUser ?? user;
    final ok = await auth.updateProfile(current.copyWith(skills: [...current.skills]..remove(skill)));
    if (!ok && context.mounted) showError(context, auth.errorMessage ?? 'Modification impossible.');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Compétences',
          trailing: RoundIconButton(
            key: const ValueKey('add-skill'),
            icon: Icons.add_rounded,
            tooltip: 'Ajouter une compétence',
            style: RoundButtonStyle.soft,
            onPressed: user.skills.length >= AppConstants.maxSkills
                ? null
                : () => showFormSheet(context, builder: (_) => _SkillForm(all: user.skills)),
          ),
        ),
        if (user.skills.isEmpty)
          const EmptyState(
            icon: Icons.psychology_rounded,
            title: 'Aucune compétence',
            subtitle: 'Ajoutez-en pour obtenir un score de compatibilité sur chaque offre.',
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final skill in user.skills)
                InputChip(
                  key: ValueKey('skill-$skill'),
                  label: Text(skill),
                  deleteButtonTooltipMessage: 'Retirer $skill',
                  onDeleted: () => _remove(context, skill),
                ),
            ],
          ),
      ],
    );
  }
}

class _SkillForm extends StatefulWidget {
  const _SkillForm({required this.all});

  final List<String> all;

  @override
  State<_SkillForm> createState() => _SkillFormState();
}

class _SkillFormState extends State<_SkillForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser!;
    final ok = await auth.updateProfile(user.copyWith(skills: [...user.skills, _name.text.trim()]));
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      showError(context, auth.errorMessage ?? 'Modification impossible.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Nouvelle compétence', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          AuthTextField(
            key: const ValueKey('skill-name'),
            label: 'Compétence',
            hint: 'Flutter, SQL, Gestion de projet…',
            icon: Icons.psychology_rounded,
            controller: _name,
            autofocus: true,
            validator: (v) => Validators.skill(v, existing: widget.all),
          ),
          const SizedBox(height: 16),
          PillButton(key: const ValueKey('skill-save'), label: 'Enregistrer', onPressed: _save),
        ],
      ),
    );
  }
}

class _ExperienceRow extends StatelessWidget {
  const _ExperienceRow(this.e);

  final Experience e;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(e.kind == ExperienceKind.education ? Icons.school_rounded : Icons.work_history_rounded, color: t.primary, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(e.title, style: text.titleSmall),
              Text([e.organization, if (e.period.isNotEmpty) e.period].join(' · '), style: text.bodySmall),
              if (e.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(e.description, style: text.bodyMedium),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ExperienceForm extends StatefulWidget {
  const _ExperienceForm({required this.userId, this.experience});

  final String userId;
  final Experience? experience;

  @override
  State<_ExperienceForm> createState() => _ExperienceFormState();
}

class _ExperienceFormState extends State<_ExperienceForm> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.experience?.title);
  late final _organization = TextEditingController(text: widget.experience?.organization);
  late final _period = TextEditingController(text: widget.experience?.period);
  late final _description = TextEditingController(text: widget.experience?.description);
  late ExperienceKind _kind = widget.experience?.kind ?? ExperienceKind.education;

  @override
  void dispose() {
    _title.dispose();
    _organization.dispose();
    _period.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await context.read<StageServices>().experiences.save(
          id: widget.experience?.id,
          userId: widget.userId,
          kind: _kind,
          title: _title.text,
          organization: _organization.text,
          period: _period.text,
          description: _description.text,
        );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    await context.read<StageServices>().experiences.delete(widget.experience!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<ExperienceKind>(
            segments: [for (final k in ExperienceKind.values) ButtonSegment(value: k, label: Text(k.label))],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 16),
          AuthTextField(label: 'Intitulé', icon: Icons.title_rounded, controller: _title, validator: Validators.required),
          const SizedBox(height: 12),
          AuthTextField(label: 'Établissement ou entreprise', icon: Icons.business_rounded, controller: _organization, validator: Validators.required),
          const SizedBox(height: 12),
          AuthTextField(label: 'Période', hint: '2023 - 2024', icon: Icons.date_range_rounded, controller: _period),
          const SizedBox(height: 12),
          AuthTextField(
            label: 'Description',
            icon: Icons.notes_rounded,
            controller: _description,
            minLines: 2,
            maxLines: 4,
            keyboardType: TextInputType.multiline,
          ),
          const SizedBox(height: 20),
          PillButton(label: 'Enregistrer', onPressed: _save),
          if (widget.experience != null) ...[
            const SizedBox(height: 8),
            PillButton(label: 'Supprimer', style: PillStyle.danger, onPressed: _delete),
          ],
        ],
      ),
    );
  }
}
