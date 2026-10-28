import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_tokens.dart';
import '../providers/connectivity_provider.dart';

/// Bandeau "mode hors-ligne" affiché en haut des écrans concernés (BNF3).
/// Indique le nombre d'actions en attente de synchronisation.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectivityProvider>(
      builder: (context, connectivity, _) {
        if (connectivity.isOnline && connectivity.pendingActionsCount == 0) {
          return const SizedBox.shrink();
        }
        final label = !connectivity.isOnline
            ? (connectivity.pendingActionsCount > 0
                ? 'Mode hors-ligne actif — ${connectivity.pendingActionsCount} action(s) en attente de synchronisation'
                : 'Mode hors-ligne actif — vos actions seront synchronisées au retour du réseau')
            : 'Synchronisation de ${connectivity.pendingActionsCount} action(s) en cours…';

        final t = AppTokens.of(context);
        return Container(
          margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: t.warningSoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                !connectivity.isOnline
                    ? Icons.wifi_off_rounded
                    : Icons.sync_rounded,
                size: 18,
                color: t.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium!
                      .copyWith(color: t.warning),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
