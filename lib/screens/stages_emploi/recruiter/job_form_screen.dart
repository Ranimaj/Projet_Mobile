import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/validators.dart';
import '../../../models/job_offer_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/stages/stage_services.dart';
import '../../../widgets/stages/ui.dart';
import '../../../widgets/auth/auth_text_field.dart';
import '../../../widgets/pill_button.dart';
import '../../../widgets/round_icon_button.dart';

/// Création et modification d'une offre.
class JobFormScreen extends StatefulWidget {
  const JobFormScreen({super.key, this.job});

  final JobOfferModel? job;

  @override
  State<JobFormScreen> createState() => _JobFormScreenState();
}

class _JobFormScreenState extends State<JobFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.job?.title);
  late final _company = TextEditingController(text: widget.job?.companyName);
  late final _location = TextEditingController(text: widget.job?.location);
  late final _duration = TextEditingController(text: widget.job?.duration);
  late final _description = TextEditingController(text: widget.job?.description);
  late final _requirements = TextEditingController(text: widget.job?.requirements);
  final _skillInput = TextEditingController();
  late final List<String> _skills = [...?widget.job?.requiredSkills];
  late JobType _type = widget.job?.type ?? JobType.stage;
  late DateTime? _deadline = widget.job?.deadline;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _company.dispose();
    _location.dispose();
    _duration.dispose();
    _description.dispose();
    _requirements.dispose();
    _skillInput.dispose();
    super.dispose();
  }

  void _addSkill() {
    final raw = _skillInput.text.replaceAll(',', ' ').trim();
    if (Validators.skill(raw, existing: _skills) != null) return;
    setState(() {
      _skills.add(raw);
      _skillInput.clear();
    });
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      helpText: 'Date limite',
      cancelText: 'Annuler',
      confirmText: 'Valider',
      context: context,
      initialDate: _deadline != null && _deadline!.isAfter(now) ? _deadline! : now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _addSkill();
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final job = widget.job;
    try {
      await context.read<StageServices>().jobs.save(
            id: job?.id,
            recruiterId: job?.recruiterId ?? context.read<AuthProvider>().currentUser!.id,
            title: _title.text,
            company: _company.text,
            type: _type,
            location: _location.text,
            duration: _duration.text,
            description: _description.text,
            requirements: _requirements.text,
            skills: _skills,
            deadline: _deadline,
            isOpen: job?.isOpen ?? true,
          );
      navigator.pop();
    } on Exception catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final deadline = _deadline;
    return DetailPage(
      title: widget.job == null ? 'Nouvelle offre' : 'Modifier l\'offre',
      bottom: PillButton(
        key: const ValueKey('job-save'),
        label: widget.job == null ? 'Publier' : 'Enregistrer',
        isLoading: _busy,
        onPressed: _save,
      ),
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<JobType>(
                segments: [for (final t in JobType.values) ButtonSegment(value: t, label: Text(t.label))],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: 16),
              AuthTextField(
                key: const ValueKey('job-title'),
                label: 'Intitulé du poste',
                icon: Icons.title_rounded,
                controller: _title,
                textCapitalization: TextCapitalization.sentences,
                validator: Validators.required,
              ),
              const SizedBox(height: 16),
              AuthTextField(
                key: const ValueKey('job-company'),
                label: 'Entreprise',
                icon: Icons.business_rounded,
                controller: _company,
                textCapitalization: TextCapitalization.words,
                validator: Validators.required,
              ),
              const SizedBox(height: 16),
              AuthTextField(
                key: const ValueKey('job-location'),
                label: 'Lieu',
                icon: Icons.place_outlined,
                controller: _location,
                textCapitalization: TextCapitalization.words,
                validator: Validators.required,
              ),
              const SizedBox(height: 16),
              AuthTextField(label: 'Durée ou contrat', hint: '6 mois, CDI…', icon: Icons.schedule_rounded, controller: _duration),
              const SizedBox(height: 16),
              AuthTextField(
                key: const ValueKey('job-description'),
                label: 'Description',
                icon: Icons.notes_rounded,
                controller: _description,
                minLines: 4,
                maxLines: 10,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                validator: Validators.required,
              ),
              const SizedBox(height: 16),
              AuthTextField(
                label: 'Prérequis',
                icon: Icons.checklist_rounded,
                controller: _requirements,
                minLines: 2,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: AuthTextField(
                      key: const ValueKey('job-skill-input'),
                      label: 'Compétences recherchées',
                      icon: Icons.psychology_rounded,
                      controller: _skillInput,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _addSkill(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  RoundIconButton(
                    key: const ValueKey('job-skill-add'),
                    icon: Icons.add_rounded,
                    tooltip: 'Ajouter la compétence',
                    size: 44,
                    style: RoundButtonStyle.soft,
                    onPressed: _addSkill,
                  ),
                ],
              ),
              if (_skills.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final skill in _skills) InputChip(label: Text(skill), onDeleted: () => setState(() => _skills.remove(skill))),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Text('Date limite', style: text.labelLarge),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickDeadline,
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: Text(deadline == null ? 'Aucune date limite' : formatDate(deadline)),
                  ),
                  if (deadline != null) TextButton(onPressed: () => setState(() => _deadline = null), child: const Text('Retirer')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
