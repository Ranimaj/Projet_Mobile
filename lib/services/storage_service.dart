import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/utils/auth_failure.dart';
import 'local_photo_store.dart';

/// Fichiers de l'app (photos de profil, cartes étudiant, affiches, CV) :
/// copiés, compressés pour les images, dans le dossier de l'app sur le
/// téléphone. Les méthodes renvoient le chemin absolu de la copie ; c'est ce
/// chemin qui est enregistré dans la base (`photoUrl`, `imagePath`...).
class StorageService {
  StorageService({Future<Directory> Function()? appDir, Future<File> Function(File, int, int)? compress})
      : _appDir = appDir ?? getApplicationDocumentsDirectory,
        _compress = compress ?? _defaultCompress;

  final Future<Directory> Function() _appDir;
  final Future<File> Function(File file, int minSide, int quality) _compress;
  static const _uuid = Uuid();

  /// Taille maximale acceptée pour une photo de profil avant compression.
  static const int maxAvatarBytes = 5 * 1024 * 1024;

  static Future<File> _defaultCompress(File file, int minSide, int quality) async {
    try {
      final dir = await getTemporaryDirectory();
      final result = await FlutterImageCompress.compressAndGetFile(
        file.absolute.path,
        '${dir.path}/${_uuid.v4()}.jpg',
        quality: quality,
        minWidth: minSide,
        minHeight: minSide,
      );
      return result != null ? File(result.path) : file;
    } catch (_) {
      return file; // compression indisponible : on garde l'original
    }
  }

  Future<String> _store(File file, String relativePath) async {
    final target = File('${(await _appDir()).path}/$relativePath');
    await target.parent.create(recursive: true);
    return (await file.copy(target.path)).path;
  }

  /// Image compressée rangée sous `[folder]/`.
  Future<String> saveImage(File file, {required String folder, int minSide = 1080, int quality = 70}) async =>
      _store(await _compress(file, minSide, quality), '$folder/${_uuid.v4()}.jpg');

  Future<List<String>> saveImages(List<File> files, {required String folder}) async =>
      [for (final f in files) await saveImage(f, folder: folder)];

  /// Photo de profil, 512 px. Un nouveau fichier à chaque envoi ; l'ancien
  /// est supprimé par l'appelant via [delete].
  Future<String> saveAvatar(File file, {required String uid}) async {
    if (!await file.exists() || await file.length() > maxAvatarBytes) {
      throw AuthFailure.fromCode('invalid-file');
    }
    return saveImage(file, folder: 'avatars/$uid', minSide: 512, quality: 80);
  }

  /// Image compressée enregistrée exactement à [relativePath].
  Future<String> saveFile(File file, {required String relativePath}) async =>
      _store(await _compress(file, 1080, 70), relativePath);

  /// Document (CV, lettre) copié tel quel sous `[folder]/`.
  Future<String> saveDocument(File file, {required String folder}) {
    final ext = file.path.contains('.') ? file.path.split('.').last : 'bin';
    return _store(file, '$folder/${_uuid.v4()}.$ext');
  }

  /// Supprime le fichier [path] s'il est sur le téléphone. Sans effet pour
  /// une image embarquée, une URL web ou un fichier absent.
  Future<void> delete(String? path) async {
    if (path == null || path.isEmpty || !isLocalImage(path)) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
