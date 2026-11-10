/// Photos de démonstration de Vente & Don (`assets/images/demo/`) : choix
/// d'une photo dans le formulaire ou la recherche par photo, et copie dans la
/// galerie de l'émulateur. Aucun article n'est créé automatiquement.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../core/theme/app_tokens.dart';

/// Photos disponibles pour la sélection manuelle dans l'application
/// (inclut les photos de démo de base et les photos ajoutées).
class DemoPhotoChoice {
  final String title;
  final String fileName;
  const DemoPhotoChoice(this.title, this.fileName);
  String get assetPath => 'assets/images/demo/$fileName';
}

const List<DemoPhotoChoice> kAvailableDemoPhotos = [
  DemoPhotoChoice('Livre d\'algorithmique', 'livre_algo.jpg'),
  DemoPhotoChoice('Lampe de bureau LED', 'lampe_bureau.jpg'),
  DemoPhotoChoice('Calculatrice scientifique', 'calculatrice.jpg'),
  DemoPhotoChoice('Veste d\'hiver', 'veste_hiver.jpg'),
  DemoPhotoChoice('Livre', 'livre.jpg'),
  DemoPhotoChoice('Pantalon', 'pantaon.jpg'),
  DemoPhotoChoice('Livre Réveille-toi', 'Livre _ Réveille-toi et brille.jpg'),
  DemoPhotoChoice('Produit IA', 'Product _ modelia_ai.jpg'),
];

/// Convertit une image d'asset en [File] local pour l'analyse IA ou l'upload.
Future<File> demoPhotoToFile(String photoFileName) async {
  final byteData = await rootBundle.load('assets/images/demo/$photoFileName');
  final tempDir = await getTemporaryDirectory();
  final target = File('${tempDir.path}/$photoFileName');
  await target.writeAsBytes(
    byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
    flush: true,
  );
  return target;
}

/// Exporte les 4 photos de démo vers le stockage public de l'émulateur
/// (`Pictures/CampusConnect`) afin qu'elles apparaissent également dans la
/// galerie Android de l'appareil.
Future<void> exportDemoPhotosToDevice() async {
  try {
    final dirs = <Directory>[];

    // Dossier Pictures public standard Android
    dirs.add(Directory('/storage/emulated/0/Pictures/CampusConnect'));
    dirs.add(Directory('/sdcard/Pictures/CampusConnect'));

    try {
      final extDirs = await getExternalStorageDirectories(type: StorageDirectory.pictures);
      if (extDirs != null) dirs.addAll(extDirs);
    } catch (_) {}

    for (final dir in dirs) {
      try {
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        for (final item in kAvailableDemoPhotos) {
          final target = File('${dir.path}/${item.fileName}');
          if (!await target.exists()) {
            final data = await rootBundle.load(item.assetPath);
            await target.writeAsBytes(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
              flush: true,
            );
          }
        }
      } catch (_) {
        // Continue sur les autres dossiers
      }
    }
  } catch (_) {
    // Ne bloque jamais l'application si l'accès stockage échoue
  }
}

/// Sélecteur visuel des 4 photos de démonstration. Permet à l'étudiant
/// d'ajouter directement une photo même si la galerie de l'émulateur est vide.
Future<File?> showDemoPhotoPickerSheet(BuildContext context) async {
  final t = AppTokens.of(context);
  final text = Theme.of(context).textTheme;

  return showModalBottomSheet<File>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Photos de démonstration', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Choisis l\'une des ${kAvailableDemoPhotos.length} photos pour tester la publication et l\'IA :',
              style: text.bodySmall,
            ),
            const SizedBox(height: 16),
            // Flexible + grille défilante : la grille garde sa hauteur
            // naturelle quand elle tient, et défile dans la feuille sinon
            // (auparavant non défilante, elle débordait dès la 3e rangée).
            Flexible(
              child: GridView.builder(
                key: const Key('demo-photo-grid'),
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.1,
                ),
                itemCount: kAvailableDemoPhotos.length,
                itemBuilder: (ctx, i) {
                  final photoChoice = kAvailableDemoPhotos[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () async {
                      try {
                        final file = await demoPhotoToFile(photoChoice.fileName);
                        if (ctx.mounted) Navigator.pop(ctx, file);
                      } catch (_) {
                        if (ctx.mounted) Navigator.pop(ctx);
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: t.surfaceMuted,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: t.outline),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Image.asset(
                              photoChoice.assetPath,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const ColoredBox(
                                color: Colors.grey,
                                child: Icon(Icons.broken_image, color: Colors.white),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              color: Colors.black.withValues(alpha: 0.65),
                              child: Text(
                                photoChoice.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
