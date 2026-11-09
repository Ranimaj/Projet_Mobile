import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/layout.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/validators.dart';
import '../../../models/job_offer_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/stages/cv_storage.dart';
import '../../../services/stages/stage_services.dart';
import '../../../widgets/stages/ui.dart';
import '../../../widgets/auth/auth_text_field.dart';
import '../../../widgets/bottom_action_bar.dart';
import '../../../widgets/pill_button.dart';

/// Candidature en quatre étapes : CV, lettre, message, vérification.
/// Sert aussi à modifier une candidature encore en attente ([existing]).
class ApplyFlowScreen extends StatefulWidget {
  const ApplyFlowScreen({super.key, required this.jobId, required this.jobTitle, required this.company, this.existing});

  final String jobId;
  final String jobTitle;
  final String company;
  final ApplicationModel? existing;

  @override
  State<ApplyFlowScreen> createState() => _ApplyFlowScreenState();
}

class _ApplyFlowScreenState extends State<ApplyFlowScreen> {
  static const _titles = ['Votre CV', 'Lettre de motivation', 'Message au recruteur', 'Vérification'];

  final _letterKey = GlobalKey<FormState>();
  final _messageKey = GlobalKey<FormState>();
  late final _letter = TextEditingController(text: widget.existing?.coverLetter);
  late final _message = TextEditingController(text: widget.existing?.message);
  late String? _cvName = widget.existing?.cvName;
  PickedCv? _pickedCv;
  int _step = 0;
  bool _busy = false;
  String? _cvError;

  @override
  void dispose() {
    _letter.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _pickCv() async {
    final services = context.read<StageServices>();
    try {
      final cv = await services.cvs.pick();
      if (cv == null || !mounted) return;
      setState(() {
        _pickedCv = cv;
        _cvName = cv.name;
        _cvError = null;
      });
    } on Exception catch (e) {
      if (mounted) showError(context, e);
    }
  }

  bool _validateStep() {
    switch (_step) {
      case 0:
        if (_cvName == null) {
          setState(() => _cvError = 'Ajoutez votre CV pour continuer.');
          return false;
        }
        return true;
      case 1:
        return _letterKey.currentState!.validate();
      case 2:
        return _messageKey.currentState!.validate();
      default:
        return true;
    }
  }

  void _next() {
    FocusScope.of(context).unfocus();
    if (!_validateStep()) return;
    if (_step == _titles.length - 1) {
      _submit();
    } else {
      setState(() => _step++);
    }
  }

  void _back() {
    FocusScope.of(context).unfocus();
    if (_step > 0) {
      setState(() => _step--);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final student = context.read<AuthProvider>().currentUser!;
    final applications = context.read<StageServices>().applications;
    final navigator = Navigator.of(context);
    final existing = widget.existing;
    try {
      if (existing == null) {
        await applications.apply(
          jobId: widget.jobId,
          student: student,
          cv: _pickedCv!,
          motivationLetter: _letter.text,
          message: _message.text,
        );
      } else {
        await applications.edit(
          existing.id,
          studentId: student.id,
          newCv: _pickedCv,
          motivationLetter: _letter.text,
          message: _message.text,
        );
      }
      if (!mounted) return;
      showSuccess(context, existing == null ? 'Candidature envoyée.' : 'Candidature modifiée.');
      setState(() => _step = 0);
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
    final last = _step == _titles.length - 1;
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.existing == null ? 'Postuler' : 'Modifier ma candidature')),
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: ContentWidth(
                  child: ListView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(kPagePadding, 4, kPagePadding, 24),
                    children: [
                      _StepBar(step: _step, count: _titles.length),
                      const SizedBox(height: 16),
                      Text('Étape ${_step + 1} sur ${_titles.length}', style: text.labelMedium),
                      const SizedBox(height: 2),
                      Text(_titles[_step], style: text.displaySmall),
                      const SizedBox(height: 4),
                      Text('${widget.jobTitle} · ${widget.company}', style: text.bodyMedium),
                      const SizedBox(height: 20),
                      switch (_step) {
                        0 => _CvStep(name: _cvName, error: _cvError, onPick: _pickCv),
                        1 => Form(
                            key: _letterKey,
                            child: AuthTextField(
                              key: const ValueKey('apply-letter'),
                              label: 'Votre lettre',
                              helper: 'Au moins ${AppConstants.minLetterLength} caractères.',
                              icon: Icons.description_outlined,
                              controller: _letter,
                              minLines: 8,
                              maxLines: 14,
                              keyboardType: TextInputType.multiline,
                              textCapitalization: TextCapitalization.sentences,
                              validator: (v) => Validators.minLength(v, AppConstants.minLetterLength, 'Lettre'),
                            ),
                          ),
                        2 => Form(
                            key: _messageKey,
                            child: AuthTextField(
                              key: const ValueKey('apply-message'),
                              label: 'Votre message',
                              helper: 'Quelques mots directement adressés au recruteur.',
                              icon: Icons.chat_bubble_outline_rounded,
                              controller: _message,
                              minLines: 4,
                              maxLines: 8,
                              keyboardType: TextInputType.multiline,
                              textCapitalization: TextCapitalization.sentences,
                              validator: (v) => Validators.minLength(v, AppConstants.minMessageLength, 'Message'),
                            ),
                          ),
                        _ => _ReviewStep(cvName: _cvName!, letter: _letter.text, message: _message.text),
                      },
                    ],
                  ),
                ),
              ),
              BottomActionBar(
                child: ContentWidth(
                  child: Row(
                    children: [
                      Expanded(
                        child: PillButton(label: _step == 0 ? 'Annuler' : 'Retour', style: PillStyle.ghost, onPressed: _busy ? null : _back),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PillButton(
                          key: const ValueKey('apply-next'),
                          label: last ? (widget.existing == null ? 'Envoyer' : 'Enregistrer') : 'Continuer',
                          isLoading: _busy,
                          onPressed: _next,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepBar extends StatelessWidget {
  const _StepBar({required this.step, required this.count});

  final int step;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 6,
              decoration: BoxDecoration(
                color: i <= step ? t.primary : t.surfaceMuted,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CvStep extends StatelessWidget {
  const _CvStep({required this.name, required this.error, required this.onPick});

  final String? name;
  final String? error;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final selected = name != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: selected ? t.primarySoft : t.surfaceMuted,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            key: const ValueKey('apply-pick-cv'),
            borderRadius: BorderRadius.circular(20),
            onTap: onPick,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
              child: Column(
                children: [
                  Icon(selected ? Icons.task_rounded : Icons.upload_file_rounded, size: 40, color: t.primary),
                  const SizedBox(height: 10),
                  Text(selected ? name! : 'Choisir mon CV', textAlign: TextAlign.center, style: text.titleSmall),
                  const SizedBox(height: 4),
                  Text(selected ? 'Touchez pour remplacer le fichier' : 'PDF, DOC ou DOCX, 5 Mo maximum', textAlign: TextAlign.center, style: text.bodySmall),
                ],
              ),
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(error!, style: text.bodySmall?.copyWith(color: t.danger)),
        ],
      ],
    );
  }
}

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({required this.cvName, required this.letter, required this.message});

  final String cvName;
  final String letter;
  final String message;

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
      children: [block('CV', cvName), block('Lettre de motivation', letter.trim()), block('Message au recruteur', message.trim())],
    );
  }
}
