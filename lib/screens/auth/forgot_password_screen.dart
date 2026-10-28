import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/auth/auth_feedback.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/auth/auth_hero.dart';
import '../../widgets/auth/auth_link.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/hero_sheet_scaffold.dart';
import '../../widgets/round_icon_button.dart';

/// Réinitialisation du mot de passe par email.
///
/// Le résultat est volontairement identique que le compte existe ou non, pour
/// ne pas permettre de deviner quels emails sont inscrits.
class ForgotPasswordScreen extends StatefulWidget {
  final String initialEmail;
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailCtrl = TextEditingController(text: widget.initialEmail.trim());
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    _clearError();
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final ok = await auth.sendPasswordReset(_emailCtrl.text);
    if (!mounted) return;
    if (ok || auth.errorCode == 'user-not-found') {
      setState(() => _sent = true);
    } else {
      setState(() => _error = auth.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return HeroSheetScaffold(
      hero: AuthHero(
        title: _sent ? 'Lien envoyé' : 'Mot de passe oublié',
        subtitle: _sent
            ? 'Vérifie ta boîte mail, et tes courriers indésirables.'
            : 'Nous t\'enverrons un lien pour choisir un nouveau mot de passe.',
        icon: _sent ? Icons.mark_email_read_outlined : Icons.mark_email_unread_outlined,
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
        AnimatedSize(
          duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(animation),
                child: child,
              ),
            ),
            child: _sent ? _buildSent() : _buildForm(auth),
          ),
        ),
      ],
    );
  }

  Widget _buildForm(AuthProvider auth) {
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('form'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthTextField(
            label: 'Email académique',
            icon: Icons.mail_outline_rounded,
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofocus: widget.initialEmail.isEmpty,
            autofillHints: const [AutofillHints.username, AutofillHints.email],
            validator: Validators.email,
            onChanged: (_) => _clearError(),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 24),
          AuthErrorBanner(message: _error, onClose: _clearError),
          PillButton(
            label: 'Envoyer le lien',
            icon: Icons.send_rounded,
            isLoading: auth.isLoading,
            onPressed: _submit,
          ),
          const SizedBox(height: 8),
          Center(child: AuthLink(label: 'Retour à la connexion', onPressed: () => Navigator.of(context).maybePop())),
        ],
      ),
    );
  }

  Widget _buildSent() {
    final t = AppTokens.of(context);
    final email = Validators.normalizeEmail(_emailCtrl.text);
    final body = Theme.of(context).textTheme.bodyLarge;
    return Column(
      key: const ValueKey('sent'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle_rounded, size: 44, color: t.success),
        const SizedBox(height: 16),
        Text.rich(
          TextSpan(
            text: 'Si un compte existe pour ',
            children: [
              TextSpan(text: email, style: const TextStyle(fontWeight: FontWeight.w700)),
              const TextSpan(text: ', un email de réinitialisation vient d\'être envoyé.'),
            ],
          ),
          style: body,
        ),
        const SizedBox(height: 24),
        PillButton(
          label: 'Retour à la connexion',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        const SizedBox(height: 8),
        Center(child: AuthLink(label: 'Utiliser une autre adresse', onPressed: () => setState(() => _sent = false))),
      ],
    );
  }
}
