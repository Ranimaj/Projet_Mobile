import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';

class PickedCv {
  const PickedCv({required this.path, required this.name});

  final String path;
  final String name;
}

class CvTooLargeException implements Exception {
  @override
  String toString() => 'Le CV dépasse 5 Mo.';
}

class CvTypeException implements Exception {
  @override
  String toString() => 'Format accepté : PDF, DOC ou DOCX.';
}

/// Choix du fichier CV et copie dans le dossier privé de l'application.
class CvStorage {
  CvStorage({Future<Directory> Function()? directory, Future<PickedCv?> Function()? picker})
      : _directory = directory ?? getApplicationDocumentsDirectory,
        _picker = picker;

  final Future<Directory> Function() _directory;
  final Future<PickedCv?> Function()? _picker;

  /// Ouvre le sélecteur ; renvoie `null` si l'utilisateur annule.
  Future<PickedCv?> pick() async {
    final picker = _picker;
    if (picker != null) return picker();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: AppConstants.cvExtensions,
    );
    final file = result?.files.single;
    if (file == null || file.path == null) return null;
    return PickedCv(path: file.path!, name: file.name);
  }

  /// Valide le fichier puis le copie sous un nom unique ; renvoie le chemin final.
  Future<String> store(PickedCv cv) async {
    final ext = p.extension(cv.name).replaceFirst('.', '').toLowerCase();
    if (!AppConstants.cvExtensions.contains(ext)) throw CvTypeException();
    final source = File(cv.path);
    if (await source.length() > AppConstants.maxCvBytes) throw CvTooLargeException();
    final root = await _directory();
    final dir = Directory(p.join(root.path, 'cvs'));
    await dir.create(recursive: true);
    final target = p.join(dir.path, '${const Uuid().v4()}.$ext');
    await source.copy(target);
    return target;
  }

  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
