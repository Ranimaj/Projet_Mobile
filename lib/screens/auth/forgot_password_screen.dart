import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/utils/validators.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/auth/auth_feedback.dart';
import '../../widgets/auth/auth_hero.dart';
import '../../widgets/auth/auth_text_field.dart';
import '../../widgets/hero_sheet_scaffold.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/round_icon_button.dart';
import 'reset_password_screen.dart';

/// Mot de passe oublié.
///
/// Avec un SMTP configuré ([AuthProvider.passwordResetByEmail]), l'étudiant
/// saisit son email et reçoit un code pour choisir un nouveau mot de passe
/// ([ResetPasswordScreen]). La réponse est la même qu'un compte existe ou
/// non.
///
/// Sans SMTP, ou pour un compte de démonstration, aucun email ne peut être
/// envoyé : l'écran explique la marche à suivre (un administrateur attribue
/// un mot de passe provisoire, que l'étudiant change après s'être connecté).
///
/// Ferme l'écran avec l'email du compte une fois le mot de passe changé.
class ForgotPasswordScreen extends StatefulWidget {
  /// Email saisi sur l'écran de connexion, rappelé pour la demande.
  final String initialEmail;
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  static const String subtitle = 'Un administrateur peut le réinitialiser pour toi.';
  static const String emailSubtitle = 'Reçois un code par email pour en choisir un nouveau.';
  static const String demoNote =
      "Compte de démonstration : il n'a pas de vraie boîte mail, aucun code n'est envoyé.";

  static const List<String> steps = [
    "Contacte l'administration de CampusConnect avec ton email académique.",
    "Un administrateur te donne un mot de passe provisoire.",
    'Connecte-toi avec, puis choisis un nouveau mot de passe dans Profil > Changer le mot de passe.',
  ];

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailCtrl =
      TextEditingController(text: Validators.normalizeEmail(widget.initialEmail));
  String? _error;
  bool _sendFailed = false;

  /// Compte de démonstration : réinitialisation par un administrateur.
  String? _adminOnlyEmail;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  void _clearError() {
    if (_error != null) {
      setState(() {
        _error = null;
        _sendFailed = false;
      });
    }
  }

  Future<void> _send() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _clearError();
    final auth = context.read<AuthProvider>();
    final ok = await auth.requestPasswordReset(_emailCtrl.text);
    if (!mounted) return;
    final request = auth.passwordReset;
    if (!ok || request == null) {
      setState(() {
        _error = auth.errorMessage;
        _sendFailed = auth.errorCode == 'email-send-failed';
      });
      return;
    }
    if (request.byAdmin) {
      setState(() => _adminOnlyEmail = request.email);
      return;
    }
    final email = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => ResetPasswordScreen(email: request.email)),
    );
    if (email != null && mounted) Navigator.of(context).pop(email);
  }

  Widget? _backButton(BuildContext context) => Navigator.of(context).canPop()
      ? RoundIconButton(
          style: RoundButtonStyle.onPhoto,
          icon: Icons.arrow_back_rounded,
          tooltip: 'Retour',
          onPressed: () => Navigator.of(context).maybePop(),
        )
      : null;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.passwordResetByEmail) return _buildAdmin(context, widget.initialEmail, demo: false);
    if (_adminOnlyEmail != null) return _buildAdmin(context, _adminOnlyEmail!, demo: true);
    return _buildEmail(context, auth);
  }

  Widget _buildEmail(BuildContext context, AuthProvider auth) {
    final text = Theme.of(context).textTheme;
    return HeroSheetScaffold(
      hero: const AuthHero(
        title: 'Mot de passe oublié',
        subtitle: ForgotPasswordScreen.emailSubtitle,
        icon: Icons.lock_reset_rounded,
      ),
      heroLeading: _backButton(context),
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AuthCompactNote(ForgotPasswordScreen.emailSubtitle),
              Text(
                "Saisis l'email de ton compte. S'il existe, un code à 6 chiffres y sera envoyé pour "
                'choisir un nouveau mot de passe.',
                style: text.bodyLarge,
              ),
              const SizedBox(height: 20),
              AuthTextField(
                key: const Key('forgot-email'),
                label: 'Email du compte',
                icon: Icons.mail_outline_rounded,
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.send,
                autofillHints: const [AutofillHints.email],
                validator: Validators.email,
                onChanged: (_) => _clearError(),
                onSubmitted: (_) => _send(),
              ),
              const SizedBox(height: 24),
              AuthErrorBanner(
                message: _error,
                onClose: _clearError,
                action: _sendFailed && !auth.isLoading ? AuthBannerAction('Réessayer', _send) : null,
              ),
              PillButton(
                key: const Key('forgot-send'),
                label: 'Envoyer le code',
                icon: Icons.send_rounded,
                isLoading: auth.isLoading,
                onPressed: _send,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: auth.isLoading ? null : () => Navigator.of(context).maybePop(),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                child: const Text('Retour à la connexion'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Réinitialisation par un administrateur : sans SMTP ([demo] faux) ou
  /// pour un compte de démonstration.
  Widget _buildAdmin(BuildContext context, String initialEmail, {required bool demo}) {
    final t = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final email = Validators.normalizeEmail(initialEmail);
    final hasEmail = email.isNotEmpty && Validators.email(email) == null;
    const steps = ForgotPasswordScreen.steps;

    return HeroSheetScaffold(
      hero: const AuthHero(
        title: 'Mot de passe oublié',
        subtitle: ForgotPasswordScreen.subtitle,
        icon: Icons.admin_panel_settings_outlined,
      ),
      heroLeading: _backButton(context),
      children: [
        const AuthCompactNote(ForgotPasswordScreen.subtitle),
        Text(
          demo
              ? ForgotPasswordScreen.demoNote
              : "L'envoi d'emails n'est pas configuré dans cette version de l'app : il n'y a pas d'email de "
                  'réinitialisation.',
          style: textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: t.primarySoft, shape: BoxShape.circle),
                    child: Text(
                      '${i + 1}',
                      style: textTheme.labelLarge?.copyWith(color: t.onPrimarySoft),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      steps[i],
                      semanticsLabel: 'Étape ${i + 1} : ${steps[i]}',
                      style: textTheme.bodyMedium,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (hasEmail) ...[
          Text.rich(
            TextSpan(
              text: 'Ton compte : ',
              children: [
                TextSpan(text: email, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
        ],
        const SizedBox(height: 8),
        PillButton(
          label: 'Retour à la connexion',
          icon: Icons.arrow_back_rounded,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}
