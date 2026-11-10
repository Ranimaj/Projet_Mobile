import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth_service.dart';
import '../../widgets/auth/auth_feedback.dart';
import '../../widgets/auth/auth_hero.dart';
import '../../widgets/auth/otp_input.dart';
import '../../widgets/hero_sheet_scaffold.dart';
import '../../widgets/pill_button.dart';
import '../auth/otp_verification_screen.dart' show DemoSmsBanner;

/// Double authentification : après chaque connexion par mot de passe,
/// l'accueil ne s'ouvre qu'avec le code à 6 chiffres.
///
/// Avec un SMTP configuré ([AuthProvider.twoFactorByEmail]), le code part à
/// l'adresse email du compte. Sinon, il n'y a pas de vrai envoi : le code
/// est affiché dans un bandeau « SMS simulé ». « Annuler » ferme la session.
class ConfirmDeviceScreen extends StatefulWidget {
  const ConfirmDeviceScreen({super.key});

  /// `•• ••• 678` : seuls les 3 derniers chiffres restent visibles.
  static String maskPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return phone;
    return '•• ••• ${digits.substring(digits.length - 3)}';
  }

  /// `a•••@esprit.tn` : la première lettre et le domaine restent visibles.
  static String maskEmail(String email) {
    final at = email.indexOf('@');
    if (at < 1) return email;
    return '${email[0]}•••${email.substring(at)}';
  }

  @override
  State<ConfirmDeviceScreen> createState() => _ConfirmDeviceScreenState();
}

class _ConfirmDeviceScreenState extends State<ConfirmDeviceScreen> {
  final _codeCtrl = TextEditingController();
  bool _codeSent = false;
  bool _wrongCode = false;
  String? _error;

  /// Envoi par email : l'envoi a échoué, « Réessayer » est proposé.
  bool _sendFailed = false;
  Timer? _timer;
  int _secondsLeft = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _send());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeCtrl.dispose();
    super.dispose();
  }

  String get _phone => context.read<AuthProvider>().currentUser?.phoneNumber ?? '';

  void _clearError() {
    if (_error != null || _wrongCode) {
      setState(() {
        _error = null;
        _wrongCode = false;
      });
    }
  }

  Future<void> _send({bool resend = false}) async {
    if (!mounted) return;
    if (context.read<AuthProvider>().twoFactorByEmail) return _sendEmail(resend: resend);
    _clearError();
    final auth = context.read<AuthProvider>();
    if (_phone.isEmpty) {
      setState(() => _error = 'Aucun numéro vérifié sur ce compte. Contacte un admin.');
      return;
    }
    final ok = await auth.sendPhoneOtp(_phone);
    if (!mounted) return;
    setState(() {
      if (ok) {
        _codeSent = true;
        _codeCtrl.clear();
      } else {
        _error = auth.errorMessage;
      }
    });
  }

  Future<void> _sendEmail({required bool resend}) async {
    _clearError();
    setState(() => _sendFailed = false);
    final auth = context.read<AuthProvider>();
    final ok = await auth.sendTwoFactorEmail(resend: resend);
    if (!mounted) return;
    final sent = auth.twoFactorEmail;
    setState(() {
      _codeSent = sent != null;
      if (ok) {
        _codeCtrl.clear();
      } else {
        _error = auth.errorMessage;
        _sendFailed = auth.errorCode == 'email-send-failed';
      }
    });
    if (ok && sent != null) _startCountdown(sent.resendIn);
  }

  void _startCountdown(Duration wait) {
    _timer?.cancel();
    setState(() => _secondsLeft = (wait.inMilliseconds / 1000).ceil());
    if (_secondsLeft == 0) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _secondsLeft = (_secondsLeft - 1).clamp(0, 9999));
      if (_secondsLeft == 0) t.cancel();
    });
  }

  Future<void> _verify([String? code]) async {
    final value = code ?? _codeCtrl.text;
    final validation = Validators.otp(value);
    if (validation != null) {
      setState(() {
        _wrongCode = true;
        _error = validation;
      });
      return;
    }
    final auth = context.read<AuthProvider>();
    final ok = auth.twoFactorByEmail ? await auth.verifyTwoFactorEmail(value) : await auth.verifyPhoneOtp(value);
    if (!mounted || ok) return; // validé : l'app ouvre l'accueil
    setState(() {
      _wrongCode = true;
      _error = auth.errorMessage;
      // Code expiré ou blocage : un code saisi ne servira plus.
      if (auth.errorCode != 'invalid-verification-code') _codeCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return auth.twoFactorByEmail ? _buildEmail(context, auth) : _buildSimulated(context, auth);
  }

  Widget _buildEmail(BuildContext context, AuthProvider auth) {
    final text = Theme.of(context).textTheme;
    final sent = auth.twoFactorEmail;
    final email = sent?.email ?? auth.currentUser?.email ?? '';
    final masked = ConfirmDeviceScreen.maskEmail(email);
    final String status;
    if (sent != null) {
      status = 'Code envoyé à $masked';
    } else if (_sendFailed) {
      status = 'Code non envoyé';
    } else {
      status = 'Envoi du code à $masked…';
    }
    final canResend = _secondsLeft == 0 && !auth.isLoading && !_sendFailed;

    return HeroSheetScaffold(
      hero: AuthHero(
        title: 'Double authentification',
        subtitle: status,
        icon: Icons.mark_email_read_outlined,
      ),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthCompactNote(status),
            Text(
              'La double authentification est active : saisis le code à 6 chiffres reçu par email pour '
              'terminer la connexion. Il est valable ${AuthService.otpValidity.inMinutes} minutes. '
              'Pense à regarder dans les spams.',
              style: text.bodyLarge,
            ),
            const SizedBox(height: 16),
            OtpInput(
              controller: _codeCtrl,
              hasError: _wrongCode,
              enabled: _codeSent && !auth.isLoading,
              onChanged: (_) => _clearError(),
              onCompleted: _verify,
            ),
            const SizedBox(height: 24),
            AuthErrorBanner(
              message: _error,
              onClose: _clearError,
              action: _sendFailed && !auth.isLoading
                  ? AuthBannerAction('Réessayer', () => _send(resend: true))
                  : null,
            ),
            PillButton(
              key: const Key('confirm-device-verify'),
              label: 'Valider',
              icon: Icons.verified_rounded,
              isLoading: auth.isLoading,
              onPressed: _codeSent ? _verify : null,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('confirm-device-resend'),
              onPressed: canResend ? () => _send(resend: true) : null,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(_secondsLeft > 0 ? 'Renvoyer le code dans $_secondsLeft s' : 'Renvoyer le code'),
            ),
            TextButton(
              key: const Key('confirm-device-logout'),
              onPressed: auth.isLoading ? null : () => context.read<AuthProvider>().logout(),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text('Annuler et se déconnecter'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSimulated(BuildContext context, AuthProvider auth) {
    final text = Theme.of(context).textTheme;
    final phone = auth.currentUser?.phoneNumber ?? '';
    final demoCode = auth.demoSmsCode;
    final status = phone.isEmpty ? 'Aucun numéro vérifié' : 'Code prêt pour le ${ConfirmDeviceScreen.maskPhone(phone)}';

    return HeroSheetScaffold(
      hero: AuthHero(
        title: 'Double authentification',
        subtitle: status,
        icon: Icons.phonelink_lock_rounded,
      ),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthCompactNote(status),
            Text(
              'La double authentification est active : saisis le code à 6 chiffres prévu pour ton numéro '
              'vérifié pour terminer la connexion. Aucun SMS n\'est envoyé : le code s\'affiche ci-dessous.',
              style: text.bodyLarge,
            ),
            const SizedBox(height: 16),
            if (_codeSent && demoCode != null) ...[
              DemoSmsBanner(code: demoCode),
              const SizedBox(height: 16),
            ],
            OtpInput(
              controller: _codeCtrl,
              hasError: _wrongCode,
              enabled: _codeSent && !auth.isLoading,
              onChanged: (_) => _clearError(),
              onCompleted: _verify,
            ),
            const SizedBox(height: 24),
            AuthErrorBanner(message: _error, onClose: _clearError),
            PillButton(
              key: const Key('confirm-device-verify'),
              label: 'Valider',
              icon: Icons.verified_rounded,
              isLoading: auth.isLoading,
              onPressed: _codeSent ? _verify : null,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('confirm-device-resend'),
              onPressed: auth.isLoading || phone.isEmpty ? null : _send,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Renvoyer le code'),
            ),
            TextButton(
              key: const Key('confirm-device-logout'),
              onPressed: auth.isLoading ? null : () => context.read<AuthProvider>().logout(),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text('Annuler et se déconnecter'),
            ),
          ],
        ),
      ],
    );
  }
}
