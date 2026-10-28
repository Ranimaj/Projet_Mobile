import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/validators.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/auth/auth_feedback.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/initials_avatar.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/round_icon_button.dart';
import '../../widgets/section_card.dart';

/// BF3 — modifier son profil : photo, nom, filière, année, compétences.
class EditProfileScreen extends StatefulWidget {
  /// Sélecteur d'image injectable (tests). Par défaut : galerie via ImagePicker.
  final Future<File?> Function()? pickImage;

  const EditProfileScreen({super.key, this.pickImage});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const _otherDepartment = 'Autre';
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _majorCtrl;
  late final TextEditingController _studentIdCtrl;
  final _skillCtrl = TextEditingController();

  String? _year;
  String? _department;
  late List<String> _skills;
  String? _skillError;
  bool _uploadingAvatar = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().currentUser!;
    _nameCtrl = TextEditingController(text: user.fullName);
    final major = (user.major ?? '').trim();
    if (major.isEmpty) {
      _department = null;
      _majorCtrl = TextEditingController();
    } else if (AppConstants.departments.contains(major)) {
      _department = major;
      _majorCtrl = TextEditingController();
    } else {
      _department = _otherDepartment;
      _majorCtrl = TextEditingController(text: major);
    }
    _studentIdCtrl = TextEditingController(text: user.studentId ?? '');
    _year = (user.year?.isEmpty ?? true) ? null : user.year;
    _skills = List.of(user.skills);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _majorCtrl.dispose();
    _studentIdCtrl.dispose();
    _skillCtrl.dispose();
    super.dispose();
  }

  static Future<File?> _pickFromGallery() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1024,
    );
    return picked == null ? null : File(picked.path);
  }

  Future<void> _changeAvatar() async {
    final file = await (widget.pickImage ?? _pickFromGallery)();
    if (file == null || !mounted) return;
    setState(() => _uploadingAvatar = true);
    final auth = context.read<AuthProvider>();
    final ok = await auth.updateAvatar(file);
    if (!mounted) return;
    setState(() => _uploadingAvatar = false);
    showAuthSnack(
      context,
      ok
          ? 'Photo de profil mise à jour.'
          : (auth.errorMessage ?? 'Envoi impossible.'),
      isError: !ok,
    );
  }

  void _addSkill() {
    final error = Validators.skill(_skillCtrl.text, existing: _skills);
    if (error != null) {
      setState(() => _skillError = error);
      return;
    }
    if (_skills.length >= AppConstants.maxSkills) {
      setState(
          () => _skillError = '${AppConstants.maxSkills} compétences maximum');
      return;
    }
    setState(() {
      _skills.add(_skillCtrl.text.trim());
      _skillCtrl.clear();
      _skillError = null;
    });
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final studentId = _studentIdCtrl.text.trim();
    final updated = auth.currentUser!.copyWith(
      fullName: _nameCtrl.text,
      major: _department == _otherDepartment
          ? _majorCtrl.text.trim()
          : (_department ?? ''),
      studentId: studentId.isEmpty ? null : studentId,
      clearStudentId: studentId.isEmpty,
      year: _year ?? '',
      skills: _skills,
    );
    final ok = await auth.updateProfile(updated);
    if (!mounted) return;
    if (ok) {
      showAuthSnack(context, 'Profil mis à jour.', isError: false);
      Navigator.of(context).maybePop();
    } else if (auth.errorMessage != null) {
      showAuthSnack(context, auth.errorMessage!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final t = AppTokens.of(context);
    final yearItems = <String>{
      ...AppConstants.studyYears,
      if (_year != null) _year!
    }.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Modifier le profil'),
        leadingWidth: 64,
        leading: Navigator.of(context).canPop()
            ? Center(
                child: RoundIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: 'Retour',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              )
            : null,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _AvatarEditor(
                  user: user,
                  busy: _uploadingAvatar,
                  onTap: auth.isLoading ? null : _changeAvatar,
                ),
                const SizedBox(height: 22),
                SectionCard(
                  title: 'Identité',
                  padding: const EdgeInsets.all(18),
                  children: [
                    AuthTextField(
                      label: 'Nom complet',
                      hint: 'Prénom Nom',
                      icon: Icons.person_outline_rounded,
                      controller: _nameCtrl,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.name],
                      validator: Validators.fullName,
                    ),
                    const SizedBox(height: 12),
                    _ReadOnlyField(
                        label: 'Email académique', value: user.email),
                    const SizedBox(height: 12),
                    AuthTextField(
                      key: const Key('student-id'),
                      label: 'Identifiant étudiant',
                      hint: 'Optionnel',
                      icon: Icons.badge_outlined,
                      controller: _studentIdCtrl,
                      textInputAction: TextInputAction.next,
                      validator: Validators.studentId,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SectionCard(
                  title: 'Parcours',
                  padding: const EdgeInsets.all(18),
                  children: [
                    const _FieldLabel('Filière'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      key: const Key('department-dropdown'),
                      initialValue: _department,
                      isExpanded: true,
                      decoration: InputDecoration(
                          prefixIcon: Icon(Icons.school_outlined,
                              size: 20, color: t.primary)),
                      items: [
                        for (final d in AppConstants.departments)
                          DropdownMenuItem<String>(value: d, child: Text(d)),
                      ],
                      onChanged: (v) => setState(() => _department = v),
                    ),
                    if (_department == _otherDepartment) ...[
                      const SizedBox(height: 12),
                      AuthTextField(
                        key: const Key('department-other'),
                        label: 'Précise ta filière',
                        icon: Icons.edit_outlined,
                        controller: _majorCtrl,
                        textInputAction: TextInputAction.next,
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Indique ta filière'
                            : Validators.major(v),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const _FieldLabel('Année d\'étude'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String?>(
                      key: const Key('year-dropdown'),
                      initialValue: _year,
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.calendar_today_outlined,
                            size: 20, color: t.primary),
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null, child: Text('Non renseignée')),
                        for (final y in yearItems)
                          DropdownMenuItem<String?>(value: y, child: Text(y)),
                      ],
                      onChanged: (v) => setState(() => _year = v),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SectionCard(
                  title: 'Compétences',
                  padding: const EdgeInsets.all(18),
                  children: [
                    if (_skills.isEmpty)
                      Text(
                        'Ajoute tes compétences pour être repéré par les recruteurs.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final skill in _skills)
                            _SkillChip(
                              key: Key('skill-$skill'),
                              label: skill,
                              onDeleted: () =>
                                  setState(() => _skills.remove(skill)),
                            ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            key: const Key('skill-field'),
                            controller: _skillCtrl,
                            textInputAction: TextInputAction.done,
                            textCapitalization: TextCapitalization.sentences,
                            onSubmitted: (_) => _addSkill(),
                            onChanged: (_) {
                              if (_skillError != null) {
                                setState(() => _skillError = null);
                              }
                            },
                            decoration: InputDecoration(
                              hintText: 'Ex. Flutter, Gestion de projet',
                              errorText: _skillError,
                              prefixIcon: Icon(Icons.star_outline_rounded,
                                  size: 20, color: t.primary),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        PillButton(
                          key: const Key('add-skill'),
                          label: 'Ajouter',
                          style: PillStyle.ghost,
                          expand: false,
                          onPressed: _addSkill,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                PillButton(
                  label: 'Enregistrer',
                  icon: Icons.check_rounded,
                  isLoading: auth.isLoading && !_uploadingAvatar,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarEditor extends StatelessWidget {
  final AppUser user;
  final bool busy;
  final VoidCallback? onTap;
  const _AvatarEditor(
      {required this.user, required this.busy, required this.onTap});

  static const double _size = 104;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Center(
      child: SizedBox(
        width: _size + 16,
        height: _size + 8,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            InitialsAvatar(
              key: const Key('edit-avatar'),
              size: _size,
              photoUrl: user.photoUrl,
              initials: user.initials,
            ),
            if (busy)
              SizedBox(
                width: _size,
                height: _size,
                child: Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: t.onPrimary),
                  ),
                ),
              ),
            Positioned(
              right: -8,
              bottom: -12,
              child: RoundIconButton(
                icon: Icons.photo_camera_rounded,
                tooltip: 'Changer la photo',
                style: RoundButtonStyle.primary,
                onPressed: busy ? null : onTap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Skill pill with a 48 dp remove target.
class _SkillChip extends StatelessWidget {
  final String label;
  final VoidCallback onDeleted;
  const _SkillChip({super.key, required this.label, required this.onDeleted});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      height: 48,
      padding: const EdgeInsets.only(left: 16),
      decoration: BoxDecoration(
        color: t.primarySoft,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge!
                  .copyWith(color: t.onPrimarySoft),
            ),
          ),
          Semantics(
            button: true,
            label: 'Retirer $label',
            excludeSemantics: true,
            child: SizedBox(
              width: 48,
              height: 48,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onDeleted,
                child:
                    Icon(Icons.close_rounded, size: 18, color: t.onPrimarySoft),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.labelLarge);
  }
}

/// Champ affiché mais non modifiable (l'email est l'identifiant du compte).
class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;
  const _ReadOnlyField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        const SizedBox(height: 6),
        Container(
          key: const Key('read-only-email'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: t.surfaceMuted,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.mail_outline_rounded,
                  size: 20, color: t.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(value,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium!
                          .copyWith(color: t.textSecondary))),
              Icon(Icons.lock_outline_rounded,
                  size: 16, color: t.textSecondary),
            ],
          ),
        ),
      ],
    );
  }
}
