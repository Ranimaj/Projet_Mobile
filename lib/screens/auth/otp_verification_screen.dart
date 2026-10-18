import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/auth_text_styles.dart';
import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/auth/auth_feedback.dart';
import '../../widgets/auth/otp_input.dart';
import '../../widgets/gradient_scaffold.dart';
import '../../widgets/pill_button.dart';

/// Vérification du numéro de téléphone par code SMS à 6 chiffres.
/// Le code est envoyé dès l'ouverture de l'écran.
class OtpVerificationScreen extends StatefulWidget {
  final String phone;

  /// `true` quand l'écran suit l'inscription : l'étape peut être remise à plus tard.
  final bool allowSkip;
  final Duration resendDelay;

  const OtpVerificationScreen({
    super.key,
    required this.phone,
    this.allowSkip = true,
    this.resendDelay = const Duration(seconds: 30),
  });

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final _codeCtrl = TextEditingController();
  Timer? _timer;
  int _secondsLeft = 0;
  bool _codeSent = false;
  bool _wrongCode = false;
  String? _error;

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

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = widget.resendDelay.inSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _secondsLeft = (_secondsLeft - 1).clamp(0, 9999));
      if (_secondsLeft == 0) t.cancel();
    });
  }

  void _clearError() {
    if (_error != null || _wrongCode) {
      setState(() {
        _error = null;
        _wrongCode = false;
      });
    }
  }

  Future<void> _send() async {
    _clearError();
    final auth = context.read<AuthProvider>();
    final ok = await auth.sendPhoneOtp(widget.phone);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _codeSent = true;
        _codeCtrl.clear();
      });
      _startCountdown();
    } else {
      setState(() => _error = auth.errorMessage);
    }
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
    final ok = await auth.verifyPhoneOtp(value);
    if (!mounted) return;
    if (ok) {
      showAuthSnack(context, 'Numéro vérifié.', isError: false);
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      setState(() {
        _wrongCode = true;
        _error = auth.errorMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final shownPhone = auth.otpPhone ?? Validators.normalizePhone(widget.phone) ?? widget.phone;
    final canResend = _secondsLeft == 0 && !auth.isLoading;
    final status = _codeSent ? 'Code envoyé au $shownPhone' : 'Envoi du code au $shownPhone…';

    return GradientScaffold(
      title: 'Vérification',
      // L'étape est dite dans le sous-titre, pas dans une pastille.
      subtitle: widget.allowSkip ? 'Dernière étape. $status' : status,
      icon: Icons.sms_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Saisis le code à 6 chiffres',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text('Il arrive par SMS en quelques secondes.', style: AuthTextStyles.helper),
          const SizedBox(height: 18),
          OtpInput(
            controller: _codeCtrl,
            hasError: _wrongCode,
            enabled: _codeSent && !auth.isLoading,
            onDark: true,
            onChanged: (_) => _clearError(),
            onCompleted: _verify,
          ),
          const SizedBox(height: 30),
          AuthErrorBanner(message: _error, onClose: _clearError, onDark: true),
          Center(
            child: PillButton(
              label: 'Vérifier',
              icon: Icons.verified_rounded,
              isLoading: auth.isLoading,
              onPressed: _codeSent ? _verify : null,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              onPressed: canResend ? _send : null,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white.withValues(alpha: 0.6),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(
                canResend ? 'Renvoyer le code' : 'Renvoyer le code dans $_secondsLeft s',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (widget.allowSkip)
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('Plus tard', style: AuthTextStyles.link),
              ),
            ),
        ],
      ),
    );
  }
}
