import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Snackbar flottant cohérent pour les écrans d'authentification.
///
/// Réservé aux confirmations (compte créé, email envoyé…). Les erreurs de
/// formulaire passent par [AuthErrorBanner], qui reste visible près des
/// champs au lieu de disparaître sous le clavier.
void showAuthSnack(BuildContext context, String message, {bool isError = true}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? AppColors.danger : AppColors.success,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

/// Action proposée dans un [AuthErrorBanner] (libellé + callback).
class AuthBannerAction {
  final String label;
  final VoidCallback onPressed;
  const AuthBannerAction(this.label, this.onPressed);
}

/// Bandeau d'erreur affiché dans la carte, au-dessus du bouton d'action.
///
/// Se replie en douceur lorsque [message] redevient `null` (p. ex. dès que
/// l'utilisateur corrige sa saisie) ; [onClose] permet de le fermer à la main.
class AuthErrorBanner extends StatelessWidget {
  final String? message;
  final VoidCallback? onClose;

  /// Action de sortie proposée sous le message (ex. « Réessayer »).
  final AuthBannerAction? action;

  /// Variante pour fond dégradé sombre : bandeau translucide blanc, texte
  /// rose pâle lisible (au lieu du rouge sur carte blanche).
  final bool onDark;

  const AuthErrorBanner({
    super.key,
    required this.message,
    this.onClose,
    this.action,
    this.onDark = false,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final duration = reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    final fg = onDark ? AppColors.authErrorOnGradient : const Color(0xFFB91C1C);
    final iconColor = onDark ? AppColors.authErrorOnGradient : AppColors.danger;
    // Séparé du fond par la teinte seule : pas de contour.
    final bg = onDark ? Colors.white.withValues(alpha: 0.16) : AppColors.danger.withValues(alpha: 0.1);

    return AnimatedSize(
      duration: duration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: message == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                key: ValueKey(message),
                padding: const EdgeInsets.only(bottom: 16),
                child: Semantics(
                  liveRegion: true,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(Icons.error_outline_rounded, size: 18, color: iconColor),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(top: 1, right: onClose == null ? 6 : 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  message!,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.35,
                                    fontWeight: FontWeight.w500,
                                    color: fg,
                                  ),
                                ),
                                if (action != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: TextButton(
                                      onPressed: action!.onPressed,
                                      style: TextButton.styleFrom(
                                        foregroundColor: iconColor,
                                        padding: EdgeInsets.zero,
                                        minimumSize: const Size(0, 32),
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                                      ),
                                      child: Text(action!.label),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (onClose != null)
                          IconButton(
                            tooltip: 'Fermer',
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                            padding: EdgeInsets.zero,
                            onPressed: onClose,
                            icon: Icon(Icons.close_rounded, size: 16, color: iconColor),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
