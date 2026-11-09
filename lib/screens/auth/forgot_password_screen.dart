import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/utils/validators.dart';
import '../../widgets/auth/auth_hero.dart';
import '../../widgets/hero_sheet_scaffold.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/round_icon_button.dart';

/// Mot de passe oublié.
///
/// Les comptes vivent sur le téléphone, sans serveur : aucun email ne peut
/// être envoyé. L'écran explique la marche à suivre : un administrateur
/// attribue un mot de passe provisoire, que l'étudiant change après s'être
/// connecté.
class ForgotPasswordScreen extends StatelessWidget {
  /// Email saisi sur l'écran de connexion, rappelé pour la demande.
  final String initialEmail;
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  static const String subtitle = 'Un administrateur peut le réinitialiser pour toi.';

  static const List<String> steps = [
    "Contacte l'administration de CampusConnect avec ton email académique.",
    "Un administrateur te donne un mot de passe provisoire.",
    'Connecte-toi avec, puis choisis un nouveau mot de passe dans Profil > Changer le mot de passe.',
  ];

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;
    final email = Validators.normalizeEmail(initialEmail);
    final hasEmail = email.isNotEmpty && Validators.email(email) == null;

    return HeroSheetScaffold(
      hero: const AuthHero(
        title: 'Mot de passe oublié',
        subtitle: subtitle,
        icon: Icons.admin_panel_settings_outlined,
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
        Text(
          "Tes données restent sur ce téléphone : il n'y a pas d'email de "
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
