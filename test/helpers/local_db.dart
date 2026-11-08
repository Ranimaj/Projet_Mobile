import 'package:campusconnect/core/utils/local_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Ouvre le stockage partagé sur SQLite « ffi » (sans plugin Flutter), en
/// mémoire par défaut, ou dans le fichier [path] pour tester un rechargement.
Future<LocalDatabase> openTestDatabase({String? path}) {
  sqfliteFfiInit();
  return LocalDatabase.open(factory: databaseFactoryFfi, path: path ?? inMemoryDatabasePath);
}

/// Ferme le stockage partagé s'il est ouvert (à appeler en tearDown).
Future<void> closeTestDatabase() async {
  if (LocalDatabase.isOpen) await LocalDatabase.instance.close();
}
