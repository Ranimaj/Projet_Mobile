import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_colors.dart';
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

        return Container(
          margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            border: Border.all(color: const Color(0xFFFED7AA)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                !connectivity.isOnline ? Icons.wifi_off_rounded : Icons.sync_rounded,
                size: 16,
                color: AppColors.accent2,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF9A3412)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
