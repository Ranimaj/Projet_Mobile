import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/validators.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/auth/auth_feedback.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/pill_button.dart';
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

    final yearItems = <String>{
      ...AppConstants.studyYears,
      if (_year != null) _year!
    }.toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Modifier le profil')),
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
                      decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.school_outlined, size: 20)),
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
                            ? 'Précise ta filière'
                            : Validators.major(v),
                      ),
                    ],
                    const SizedBox(height: 16),
                    const _FieldLabel('Année d\'étude'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String?>(
                      key: const Key('year-dropdown'),
                      initialValue: _year,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.calendar_today_outlined,
                            size: 20, color: AppColors.lavender),
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
                            InputChip(
                              label: Text(skill),
                              onDeleted: () =>
                                  setState(() => _skills.remove(skill)),
                              deleteIcon:
                                  const Icon(Icons.close_rounded, size: 16),
                              deleteIconColor: AppColors.textSecondary,
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
                              prefixIcon: const Icon(Icons.star_outline_rounded,
                                  size: 20, color: AppColors.lavender),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 46,
                          child: FilledButton.tonal(
                            onPressed: _addSkill,
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('Ajouter'),
                          ),
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

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        children: [
          Container(
            width: 104,
            height: 104,
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
                color: AppColors.primary, shape: BoxShape.circle),
            child: CircleAvatar(
              backgroundColor: AppColors.surface,
              backgroundImage: user.photoUrl == null
                  ? null
                  : CachedNetworkImageProvider(user.photoUrl!),
              child: busy
                  ? const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.5))
                  : user.photoUrl == null
                      ? Text(user.initials,
                          style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary))
                      : null,
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Material(
              color: AppColors.primary2,
              shape: const CircleBorder(
                  side: BorderSide(color: Colors.white, width: 2)),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: busy ? null : onTap,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.photo_camera_rounded,
                      size: 16, color: Colors.white),
                ),
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
    return Text(
      text,
      style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary),
    );
  }
}

/// Champ affiché mais non modifiable (l'email est l'identifiant du compte).
class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;
  const _ReadOnlyField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: AppColors.border.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.mail_outline_rounded,
                  size: 20, color: AppColors.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(value,
                      style: const TextStyle(color: AppColors.textSecondary))),
              const Icon(Icons.lock_outline_rounded,
                  size: 16, color: AppColors.textSecondary),
            ],
          ),
        ),
      ],
    );
  }
}
