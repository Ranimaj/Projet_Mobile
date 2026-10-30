import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme/app_tokens.dart';
import '../models/annonce_model.dart';

/// Lieu d'une annonce (ex. objet trouvé) + ouverture dans OpenStreetMap.
class AnnonceLocationCard extends StatelessWidget {
  final AnnonceModel annonce;
  const AnnonceLocationCard({super.key, required this.annonce});

  Future<void> _openMap(BuildContext context) async {
    final lat = annonce.latitude!;
    final lon = annonce.longitude!;
    final uri = Uri.parse('https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=17/$lat/$lon');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Impossible d'ouvrir la carte.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.outline),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Icon(Icons.place_rounded, size: 20, color: t.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Lieu', style: text.bodySmall),
              const SizedBox(height: 2),
              Text(annonce.locationName ?? 'Position enregistrée', style: text.titleSmall),
            ],
          ),
        ),
        TextButton(onPressed: () => _openMap(context), child: const Text('Voir la carte')),
      ]),
    );
  }
}
