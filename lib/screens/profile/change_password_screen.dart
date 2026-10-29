import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/auth/auth_feedback.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/auth/password_strength_meter.dart';
import '../../widgets/auth/auth_hero.dart';
import '../../widgets/hero_sheet_scaffold.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/round_icon_button.dart';

/// Changement de mot de passe (ré-authentification par l'ancien mot de passe).
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok = await auth.changePassword(
      currentPassword: _currentCtrl.text,
      newPassword: _newCtrl.text,
    );
    if (!mounted) return;
    if (ok) {
      showAuthSnack(context, 'Mot de passe mis à jour.', isError: false);
      Navigator.of(context).maybePop();
    } else if (auth.errorMessage != null) {
      showAuthSnack(context, auth.errorMessage!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    const subtitle = 'Pour ta sécurité, confirme d\'abord ton mot de passe actuel.';

    return HeroSheetScaffold(
      hero: const AuthHero(
        title: 'Changer le mot de passe',
        subtitle: subtitle,
        icon: Icons.lock_reset_rounded,
      ),
      heroLeading: Navigator.of(context).canPop()
          ? RoundIconButton(
              style: RoundButtonStyle.onPhoto,
              icon: Icons.arrow_back_rounded,
              tooltip: 'Retour',
              onPressed: () => Navigator.of(context).maybePop(),
            )
          : null,
      children: [
        const AuthCompactNote(subtitle),
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthTextField(
                label: 'Mot de passe actuel',
                hint: '••••••••',
                icon: Icons.lock_outline_rounded,
                controller: _currentCtrl,
                isPassword: true,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.password],
                validator: Validators.loginPassword,
              ),
              const SizedBox(height: 16),
              AuthTextField(
                label: 'Nouveau mot de passe',
                hint: '8 caractères min., lettres et chiffres',
                icon: Icons.lock_reset_rounded,
                controller: _newCtrl,
                isPassword: true,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                validator: (v) {
                  final error = Validators.newPassword(v);
                  if (error != null) return error;
                  return v == _currentCtrl.text ? 'Identique au mot de passe actuel' : null;
                },
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              PasswordStrengthMeter(password: _newCtrl.text),
              const SizedBox(height: 16),
              AuthTextField(
                label: 'Confirmer le nouveau mot de passe',
                hint: 'Répète le nouveau mot de passe',
                icon: Icons.verified_user_outlined,
                controller: _confirmCtrl,
                isPassword: true,
                textInputAction: TextInputAction.done,
                validator: Validators.confirmPassword(() => _newCtrl.text),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 24),
              PillButton(label: 'Mettre à jour', isLoading: auth.isLoading, onPressed: _submit),
            ],
          ),
        ),
      ],
    );
  }
}
