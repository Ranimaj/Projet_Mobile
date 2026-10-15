import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Upload de fichiers (images d'articles, CV, posters d'événements) avec
/// compression automatique — fonctionnalité avancée du module Vente & Don.
class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  static const _uuid = Uuid();

  /// Compresse une image avant envoi pour économiser bande passante et
  /// stockage (fonctionnalité avancée "upload multi-images compressées").
  Future<File> _compressImage(File file) async {
    final dir = await getTemporaryDirectory();
    final targetPath = '${dir.path}/${_uuid.v4()}.jpg';

    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 70,
      minWidth: 1080,
      minHeight: 1080,
    );
    return result != null ? File(result.path) : file;
  }

  Future<String> uploadImage(File file, {required String folder}) async {
    final compressed = await _compressImage(file);
    final ref = _storage.ref().child('$folder/${_uuid.v4()}.jpg');
    final task = await ref.putFile(compressed);
    return task.ref.getDownloadURL();
  }

  Future<List<String>> uploadImages(List<File> files, {required String folder}) async {
    final urls = <String>[];
    for (final file in files) {
      urls.add(await uploadImage(file, folder: folder));
    }
    return urls;
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
      // fichier déjà supprimé ou inaccessible — on ignore
    }
  }
}
