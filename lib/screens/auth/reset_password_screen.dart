import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/auth/auth_feedback.dart';
import '../../widgets/auth/auth_hero.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/auth/otp_input.dart';
import '../../widgets/auth/password_strength_meter.dart';
import '../../widgets/hero_sheet_scaffold.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/round_icon_button.dart';

/// Mot de passe oublié, 2e étape : le code reçu par email et le nouveau
/// mot de passe (mêmes règles qu'à l'inscription, avec confirmation).
///
/// Le texte est le même qu'un compte existe ou non pour [email]. Ferme
/// l'écran avec [email] une fois le mot de passe changé.
class ResetPasswordScreen extends StatefulWidget {
  final String email;
  const ResetPasswordScreen({super.key, required this.email});

  static const String neutralMessage = "Si un compte existe, un code vient d'être envoyé";

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _error;
  bool _wrongCode = false;

  /// Le renvoi du code a échoué : « Réessayer » est proposé.
  bool _sendFailed = false;
  Timer? _timer;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    final sent = context.read<AuthProvider>().passwordReset;
    if (sent != null) _startCountdown(sent.resendIn);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_error != null || _wrongCode) {
      setState(() {
        _error = null;
        _wrongCode = false;
      });
    }
  }

  void _startCountdown(Duration wait) {
    _timer?.cancel();
    _secondsLeft = (wait.inMilliseconds / 1000).ceil();
    if (_secondsLeft == 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _secondsLeft = (_secondsLeft - 1).clamp(0, 9999));
      if (_secondsLeft == 0) t.cancel();
    });
  }

  Future<void> _resend() async {
    _clearError();
    setState(() => _sendFailed = false);
    final auth = context.read<AuthProvider>();
    final ok = await auth.requestPasswordReset(widget.email, resend: true);
    if (!mounted) return;
    setState(() {
      if (ok) {
        _codeCtrl.clear();
        final sent = auth.passwordReset;
        if (sent != null) _startCountdown(sent.resendIn);
      } else {
        _error = auth.errorMessage;
        _sendFailed = auth.errorCode == 'email-send-failed';
      }
    });
  }

  Future<void> _submit() async {
    final codeError = Validators.otp(_codeCtrl.text);
    final formOk = _formKey.currentState?.validate() ?? false;
    if (codeError != null) {
      setState(() {
        _wrongCode = true;
        _error = codeError;
      });
      return;
    }
    if (!formOk) return;
    final auth = context.read<AuthProvider>();
    final ok = await auth.resetPasswordWithEmailCode(
      email: widget.email,
      code: _codeCtrl.text,
      newPassword: _passwordCtrl.text,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(widget.email);
      return;
    }
    setState(() {
      _error = auth.errorMessage;
      _wrongCode = auth.errorCode != 'weak-password';
      // Code expiré ou blocage : le code saisi ne servira plus.
      if (auth.errorCode != 'invalid-verification-code' && auth.errorCode != 'weak-password') _codeCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final text = Theme.of(context).textTheme;
    final canResend = _secondsLeft == 0 && !auth.isLoading;

    return HeroSheetScaffold(
      hero: const AuthHero(
        title: 'Nouveau mot de passe',
        subtitle: ResetPasswordScreen.neutralMessage,
        icon: Icons.mark_email_read_outlined,
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
                const AuthCompactNote(ResetPasswordScreen.neutralMessage),
                Text.rich(
                  TextSpan(
                    text: 'Si un compte existe pour ',
                    children: [
                      TextSpan(text: widget.email, style: const TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(
                        text: ", un code à 6 chiffres vient d'y être envoyé. Il est valable "
                            '${AuthService.passwordResetValidity.inMinutes} minutes. '
                            'Pense à regarder dans les spams.',
                      ),
                    ],
                  ),
                  key: const Key('reset-neutral'),
                  style: text.bodyLarge,
                ),
                const SizedBox(height: 16),
                OtpInput(
                  controller: _codeCtrl,
                  hasError: _wrongCode,
                  enabled: !auth.isLoading,
                  onChanged: (_) => _clearError(),
                ),
                const SizedBox(height: 20),
                AuthTextField(
                  key: const Key('reset-password'),
                  label: 'Nouveau mot de passe',
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
                  key: const Key('reset-confirm'),
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
                AuthErrorBanner(
                  message: _error,
                  onClose: _clearError,
                  action: _sendFailed && !auth.isLoading ? AuthBannerAction('Réessayer', _resend) : null,
                ),
                PillButton(
                  key: const Key('reset-submit'),
                  label: 'Changer le mot de passe',
                  icon: Icons.check_rounded,
                  isLoading: auth.isLoading,
                  onPressed: _submit,
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const Key('reset-resend'),
                  onPressed: canResend ? _resend : null,
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(_secondsLeft > 0 ? 'Renvoyer le code dans $_secondsLeft s' : 'Renvoyer le code'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
