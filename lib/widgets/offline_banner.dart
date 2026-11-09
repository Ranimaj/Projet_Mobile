import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme/app_tokens.dart';
import '../providers/connectivity_provider.dart';

/// Bandeau "mode hors-ligne" affiché en haut des écrans concernés (BNF3).
/// Les données sont sur le téléphone : seuls les services web en dépendent.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectivityProvider>(
      builder: (context, connectivity, _) {
        if (connectivity.isOnline) return const SizedBox.shrink();
        const label = 'Hors-ligne — tes données restent disponibles ; l\'assistant et les cartes '
            'reviendront avec le réseau';

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
              Icon(Icons.wifi_off_rounded, size: 18, color: t.warning),
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
