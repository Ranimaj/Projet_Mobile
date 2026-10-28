import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/auth/auth_feedback.dart';
import '../../widgets/auth/otp_input.dart';
import '../../widgets/auth/auth_hero.dart';
import '../../widgets/auth/auth_link.dart';
import '../../widgets/hero_sheet_scaffold.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/round_icon_button.dart';

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

    final t = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return HeroSheetScaffold(
      hero: AuthHero(
        title: 'Vérification',
        // L'étape est dite dans le sous-titre, pas dans une pastille.
        subtitle: widget.allowSkip ? 'Dernière étape. $status' : status,
        icon: Icons.sms_outlined,
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Saisis le code à 6 chiffres', style: textTheme.labelLarge),
            const SizedBox(height: 4),
            Text('Il arrive par SMS en quelques secondes.', style: textTheme.bodyMedium),
            const SizedBox(height: 16),
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
              label: 'Vérifier',
              icon: Icons.verified_rounded,
              isLoading: auth.isLoading,
              onPressed: _codeSent ? _verify : null,
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: canResend ? _send : null,
                style: TextButton.styleFrom(
                  foregroundColor: t.primary,
                  disabledForegroundColor: t.textSecondary,
                  minimumSize: const Size(48, 48),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                  canResend ? 'Renvoyer le code' : 'Renvoyer le code dans $_secondsLeft s',
                  style: textTheme.bodyMedium?.copyWith(color: canResend ? t.primary : t.textSecondary, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            if (widget.allowSkip)
              Center(
                child: AuthLink(
                  label: 'Plus tard',
                  onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
