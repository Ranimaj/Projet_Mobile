import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/auth/auth_feedback.dart';
import '../../widgets/auth/password_strength_meter.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/auth/auth_hero.dart';
import '../../widgets/auth/auth_link.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/hero_sheet_scaffold.dart';
import '../../widgets/round_icon_button.dart';
import 'otp_verification_screen.dart';

/// Inscription étudiante (BF1) — crée le compte Firebase Auth + profil Firestore.
/// Si un numéro de téléphone est fourni, enchaîne sur la vérification OTP.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String? _optionalPhone(String? v) => (v == null || v.trim().isEmpty) ? null : Validators.phone(v);

  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    _clearError();
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok = await auth.register(
      fullName: _nameCtrl.text,
      email: _emailCtrl.text,
      password: _passwordCtrl.text,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() => _error = auth.errorMessage);
      return;
    }

    TextInput.finishAutofillContext();
    showAuthSnack(context, 'Compte créé. Vérifie ton email académique.', isError: false);
    final phone = _phoneCtrl.text.trim();
    if (phone.isNotEmpty) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => OtpVerificationScreen(phone: phone)),
      );
    } else {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return HeroSheetScaffold(
      hero: const AuthHero(
        title: 'Rejoindre CampusConnect',
        subtitle: 'Utilise ton email académique pour être vérifié',
        icon: Icons.person_add_alt_1_rounded,
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
        Form(
          key: _formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthTextField(
                  label: 'Nom complet',
                  icon: Icons.person_outline_rounded,
                  controller: _nameCtrl,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  validator: Validators.fullName,
                  onChanged: (_) => _clearError(),
                ),
                const SizedBox(height: 16),
                AuthTextField(
                  label: 'Email académique',
                  icon: Icons.mail_outline_rounded,
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.username, AutofillHints.email],
                  validator: Validators.email,
                  onChanged: (_) => _clearError(),
                ),
                const SizedBox(height: 16),
                AuthTextField(
                  label: 'Téléphone (optionnel)',
                  helper: 'Pour vérifier ton compte par SMS, juste après l\'inscription.',
                  icon: Icons.phone_outlined,
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  validator: _optionalPhone,
                ),
                const SizedBox(height: 16),
                AuthTextField(
                  label: 'Mot de passe',
                  icon: Icons.lock_outline_rounded,
                  controller: _passwordCtrl,
                  isPassword: true,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: Validators.newPassword,
                  onChanged: (_) => setState(() => _error = null),
                ),
                const SizedBox(height: 10),
                PasswordStrengthMeter(password: _passwordCtrl.text),
                const SizedBox(height: 16),
                AuthTextField(
                  label: 'Confirmer le mot de passe',
                  icon: Icons.verified_user_outlined,
                  controller: _confirmCtrl,
                  isPassword: true,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: Validators.confirmPassword(() => _passwordCtrl.text),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 24),
                AuthErrorBanner(message: _error, onClose: _clearError),
                PillButton(
                  label: 'Créer mon compte',
                  icon: Icons.arrow_forward_rounded,
                  isLoading: auth.isLoading,
                  onPressed: _submit,
                ),
                const SizedBox(height: 8),
                Center(
                  child: AuthLink(label: 'J\'ai déjà un compte', onPressed: () => Navigator.of(context).maybePop()),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
