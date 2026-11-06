import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// true si [url] désigne une photo encore stockée sur le téléphone (pas
/// encore envoyée dans Firebase Storage).
bool isLocalImage(String url) => !url.startsWith('http://') && !url.startsWith('https://');

/// Photos d'articles publiées sans réseau : copiées dans le dossier documents
/// de l'app (le cache d'image_picker peut être vidé par Android) puis
/// envoyées dans Storage au retour du réseau par [ArticleProvider].
class LocalPhotoStore {
  LocalPhotoStore({Future<Directory> Function()? appDir})
      : _appDir = appDir ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _appDir;
  static const _uuid = Uuid();

  /// Copie [file] et renvoie le chemin absolu de la copie.
  Future<String> keep(File file) async {
    final dir = Directory('${(await _appDir()).path}/article_photos');
    if (!await dir.exists()) await dir.create(recursive: true);
    final copy = await file.copy('${dir.path}/${_uuid.v4()}.jpg');
    return copy.path;
  }

  /// La copie existe-t-elle sur ce téléphone ? (Les chemins locaux d'un
  /// article publié depuis un autre appareil n'existent pas ici.)
  bool exists(String path) => File(path).existsSync();

  File fileOf(String path) => File(path);

  Future<void> discard(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
