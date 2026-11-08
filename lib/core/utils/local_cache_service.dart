import 'package:cloud_firestore/cloud_firestore.dart';

import 'local_database.dart';

/// Cache local générique : conserve la dernière copie connue de chaque
/// collection (articles, annonces, événements, offres) pour que
/// l'utilisateur puisse consulter l'app hors-ligne (BNF3).
///
/// Chaque document est stocké sous forme de Map<String,dynamic> indexé par
/// son id, sous la clé de collection passée en paramètre ([boxName], ex.
/// `events_box`), dans le stockage SQLite partagé [LocalDatabase] : lecture
/// synchrone depuis la mémoire, écriture enregistrée en arrière-plan.
///
/// Les valeurs Firestore (`Timestamp`, `GeoPoint`, `DocumentReference`) sont
/// converties avant stockage. Les modèles relisent indifféremment un
/// `Timestamp` ou une date ISO 8601, donc le cache reste lisible tel quel.
class LocalCacheService {
  LocalDatabase get _store => LocalDatabase.instance;

  /// Remplace le cache d'une collection par la liste fraîchement lue
  /// depuis Firestore (appelé après chaque lecture réseau réussie).
  Future<void> cacheCollection(
    String boxName,
    Map<String, Map<String, dynamic>> documentsById,
  ) async {
    await _store.replaceCollection(boxName, {
      for (final e in documentsById.entries) e.key: sanitize(e.value) as Map<String, dynamic>,
    });
  }

  /// Met à jour / insère un seul document dans le cache (après une
  /// création ou modification locale, en attendant la synchro).
  Future<void> upsert(String boxName, String id, Map<String, dynamic> data) async {
    await _store.putDocument(boxName, id, sanitize(data) as Map<String, dynamic>);
  }

  Future<void> removeFromCache(String boxName, String id) async {
    await _store.removeDocument(boxName, id);
  }

  /// Lit tout le cache d'une collection (utilisé quand l'app est hors-ligne
  /// ou le temps que la première réponse réseau arrive).
  Map<String, Map<String, dynamic>> readCollection(String boxName) => _store.readCollection(boxName);

  /// Rend une valeur Firestore stockable en JSON, récursivement.
  static dynamic sanitize(dynamic value) {
    if (value is Timestamp) return value.toDate().toUtc().toIso8601String();
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is GeoPoint) return {'latitude': value.latitude, 'longitude': value.longitude};
    if (value is DocumentReference) return value.path;
    if (value is Map) {
      return <String, dynamic>{for (final e in value.entries) e.key.toString(): sanitize(e.value)};
    }
    if (value is Iterable) return value.map(sanitize).toList();
    return value;
  }
}
