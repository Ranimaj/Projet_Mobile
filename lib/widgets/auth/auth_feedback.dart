import 'package:flutter/material.dart';
import '../../core/theme/app_tokens.dart';

/// Snackbar flottant cohérent pour les écrans d'authentification.
///
/// Réservé aux confirmations (compte créé, email envoyé…). Les erreurs de
/// formulaire passent par [AuthErrorBanner], qui reste visible près des
/// champs au lieu de disparaître sous le clavier.
void showAuthSnack(BuildContext context, String message, {bool isError = true}) {
  final t = AppTokens.of(context);
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? t.danger : t.success,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            Icon(isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                color: t.onPrimary, size: 20),
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

  const AuthErrorBanner({
    super.key,
    required this.message,
    this.onClose,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final duration = reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    final t = AppTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

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
                    padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
                    decoration: BoxDecoration(
                      color: t.dangerSoft,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Icon(Icons.error_outline_rounded, size: 18, color: t.danger),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(top: 11, bottom: 7, right: onClose == null ? 12 : 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  message!,
                                  style: textTheme.bodySmall
                                      ?.copyWith(fontWeight: FontWeight.w500, color: t.danger),
                                ),
                                if (action != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: TextButton(
                                      onPressed: action!.onPressed,
                                      style: TextButton.styleFrom(
                                        foregroundColor: t.danger,
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                        minimumSize: const Size(48, 48),
                                        textStyle: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
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
                            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
                            padding: EdgeInsets.zero,
                            onPressed: onClose,
                            icon: Icon(Icons.close_rounded, size: 18, color: t.danger),
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
