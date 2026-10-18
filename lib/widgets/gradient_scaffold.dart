import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/auth_text_styles.dart';
import 'auth/auth_entrance.dart';

/// Écran d'authentification sur un champ de couleur plein écran : un seul bleu
/// uni (pas de dégradé, pas de formes décoratives), bouton retour + pastille
/// d'icône, titre / sous-titre dans le tiers supérieur, puis [child].
///
/// Le contenu est dans SafeArea + SingleChildScrollView : le clavier ne
/// recouvre jamais les champs. Le fond reste plein écran même quand le
/// contenu défile.
///
/// Le nom est conservé pour l'historique de l'API ; [gradient] reste
/// disponible mais n'est plus utilisé par défaut.
class GradientScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool showBack;
  final Widget child;

  /// Couleur unie du fond (par défaut [AppColors.authField]).
  final Color color;

  /// Dégradé optionnel ; `null` (défaut) = couleur unie [color].
  final Gradient? gradient;

  const GradientScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.icon = Icons.school_rounded,
    this.showBack = true,
    this.color = AppColors.authField,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = showBack && Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: color,
      body: DecoratedBox(
        decoration: BoxDecoration(color: gradient == null ? color : null, gradient: gradient),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight - 36),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 44,
                          child: canPop
                              ? Align(
                                  alignment: Alignment.centerLeft,
                                  child: IconButton(
                                    tooltip: 'Retour',
                                    onPressed: () => Navigator.of(context).maybePop(),
                                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 16),
                        AuthEntrance(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(icon, color: Colors.white, size: 26),
                              ),
                              const SizedBox(height: 22),
                              Text(title, style: AuthTextStyles.title(context)),
                              const SizedBox(height: 8),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: Text(subtitle,
                                    key: ValueKey(subtitle), style: AuthTextStyles.subtitle(context)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 44),
                        AuthEntrance(
                          delay: const Duration(milliseconds: 90),
                          offset: 28,
                          child: child,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
