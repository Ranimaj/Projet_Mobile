import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/utils/auth_failure.dart';

/// Upload de fichiers (images d'articles, CV, posters d'événements, photos de
/// profil) avec compression automatique — fonctionnalité avancée du module
/// Vente & Don réutilisée par la Gestion des Utilisateurs.
class StorageService {
  final FirebaseStorage _storage;
  static const _uuid = Uuid();

  /// Taille maximale acceptée pour une photo de profil avant compression.
  static const int maxAvatarBytes = 5 * 1024 * 1024;

  StorageService({FirebaseStorage? storage}) : _storage = storage ?? FirebaseStorage.instance;

  /// Compresse une image avant envoi pour économiser bande passante et
  /// stockage (fonctionnalité avancée "upload multi-images compressées").
  Future<File> _compressImage(File file, {int minSide = 1080, int quality = 70}) async {
    final dir = await getTemporaryDirectory();
    final targetPath = '${dir.path}/${_uuid.v4()}.jpg';

    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: quality,
      minWidth: minSide,
      minHeight: minSide,
    );
    return result != null ? File(result.path) : file;
  }

  Future<String> uploadImage(File file, {required String folder}) async {
    final compressed = await _compressImage(file);
    final ref = _storage.ref().child('$folder/${_uuid.v4()}.jpg');
    final task = await ref.putFile(compressed);
    return task.ref.getDownloadURL();
  }

  /// Envoie [file] (compressé) à [remotePath] et renvoie ce chemin Storage,
  /// pas une URL : les pièces sensibles (carte étudiant) ne sont lues que par
  /// leur propriétaire et les admins, qui résolvent l'URL à la demande.
  Future<String> uploadFile(File file, {required String remotePath}) async {
    final compressed = await _compressImage(file);
    await _storage
        .ref()
        .child(remotePath)
        .putFile(compressed, SettableMetadata(contentType: 'image/jpeg'));
    return remotePath;
  }

  Future<List<String>> uploadImages(List<File> files, {required String folder}) async {
    final urls = <String>[];
    for (final file in files) {
      urls.add(await uploadImage(file, folder: folder));
    }
    return urls;
  }

  /// Photo de profil : rangée sous `avatars/{uid}/` (chemin protégé par les
  /// règles Storage), compressée en 512 px. Chaque envoi crée un nouveau
  /// fichier pour que l'URL change et que les caches se rafraîchissent ;
  /// l'ancienne photo est supprimée par l'appelant via [deleteByUrl].
  Future<String> uploadAvatar(File file, {required String uid}) async {
    if (!await file.exists() || await file.length() > maxAvatarBytes) {
      throw AuthFailure.fromCode('invalid-file');
    }
    final compressed = await _compressImage(file, minSide: 512, quality: 80);
    final ref = _storage.ref().child('avatars/$uid/${DateTime.now().millisecondsSinceEpoch}.jpg');
    final task = await ref.putFile(compressed, SettableMetadata(contentType: 'image/jpeg'));
    return task.ref.getDownloadURL();
  }

  /// Upload d'un document (CV, lettre de motivation) — module Stage & Emploi.
  Future<String> uploadDocument(File file, {required String folder}) async {
    final ext = file.path.split('.').last;
    final ref = _storage.ref().child('$folder/${_uuid.v4()}.$ext');
    final task = await ref.putFile(file);
    return task.ref.getDownloadURL();
  }

  Future<void> deleteByUrl(String url) async {
    try {
      await _storage.refFromURL(url).delete();
    } catch (_) {
      // fichier déjà supprimé, hébergé ailleurs (photo Google) ou inaccessible — on ignore
    }
  }
}
