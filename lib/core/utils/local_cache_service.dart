import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Hive ne sait pas stocker le type Firestore [Timestamp] : on le convertit
/// en [DateTime] (type natif Hive), y compris dans les maps et listes imbriquées.
/// Utilisé pour les payloads de la file hors-ligne : rejoués vers Firestore,
/// les DateTime redeviennent des Timestamp (une chaîne ISO resterait une chaîne).
/// Le cache de lecture, lui, passe par [LocalCacheService.sanitize].
dynamic toHiveSafe(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is Map) return value.map((k, v) => MapEntry(k, toHiveSafe(v)));
  if (value is List) return value.map(toHiveSafe).toList();
  return value;
}

/// Cache local générique (Hive) : conserve la dernière copie connue de
/// chaque collection (articles, annonces, événements, offres) pour que
/// l'utilisateur puisse consulter l'app hors-ligne (BNF3).
///
/// Chaque document est stocké sous forme de Map<String,dynamic> indexé
/// par son id, dans la box dont le nom est passé en paramètre.
///
/// Hive ne sait écrire que des types primitifs : les valeurs Firestore
/// (`Timestamp`, `GeoPoint`, `DocumentReference`) sont converties avant
/// stockage. Les modèles relisent indifféremment un `Timestamp` ou une date
/// ISO 8601, donc le cache reste lisible tel quel.
class LocalCacheService {
  Box _box(String boxName) => Hive.box(boxName);

  /// Remplace le cache d'une collection par la liste fraîchement lue
  /// depuis Firestore (appelé après chaque lecture réseau réussie).
  Future<void> cacheCollection(
    String boxName,
    Map<String, Map<String, dynamic>> documentsById,
  ) async {
    final box = _box(boxName);
    await box.clear();
    await box.putAll({
      for (final e in documentsById.entries) e.key: sanitize(e.value),
    });
  }

  /// Met à jour / insère un seul document dans le cache (après une
  /// création ou modification locale, en attendant la synchro).
  Future<void> upsert(String boxName, String id, Map<String, dynamic> data) async {
    await _box(boxName).put(id, sanitize(data));
  }

  Future<void> removeFromCache(String boxName, String id) async {
    await _box(boxName).delete(id);
  }

  /// Lit tout le cache d'une collection (utilisé quand l'app est hors-ligne
  /// ou le temps que la première réponse réseau arrive).
  Map<String, Map<String, dynamic>> readCollection(String boxName) {
    final box = _box(boxName);
    return {
      for (final key in box.keys)
        key.toString(): Map<String, dynamic>.from(box.get(key) as Map),
    };
  }

  /// Rend une valeur Firestore stockable par Hive, récursivement.
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
