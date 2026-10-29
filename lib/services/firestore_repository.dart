import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../core/utils/local_cache_service.dart';
import '../core/utils/offline_queue_service.dart';

/// Dépôt générique offline-first : chaque module (Vente & Don, Annonces,
/// Événements, Stage & Emploi) l'utilise pour parler à Firestore sans
/// jamais bloquer l'interface quand le réseau est absent.
///
/// Stratégie :
///  - lecture : tente Firestore, met le résultat en cache local, et si la
///    requête échoue (hors-ligne), retombe silencieusement sur le cache ;
///  - écriture : tente Firestore directement si en ligne, sinon enregistre
///    l'action dans [OfflineQueueService] + met à jour le cache local de
///    façon optimiste pour que l'UI réagisse immédiatement.
class FirestoreRepository<T> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final LocalCacheService cache = LocalCacheService();
  final OfflineQueueService queue = OfflineQueueService();
  static const _uuid = Uuid();

  final String collectionName;
  final String cacheBoxName;
  final T Function(String id, Map<String, dynamic> map) fromMap;
  final Map<String, dynamic> Function(T item) toMap;

  FirestoreRepository({
    required this.collectionName,
    required this.cacheBoxName,
    required this.fromMap,
    required this.toMap,
  });

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection(collectionName);

  /// Lecture avec repli automatique sur le cache si le réseau est indisponible.
  Future<List<T>> fetchAll({Query<Map<String, dynamic>>? customQuery, required bool isOnline}) async {
    if (isOnline) {
      try {
        final snapshot = await (customQuery ?? _col).get();
        final byId = <String, Map<String, dynamic>>{};
        for (final doc in snapshot.docs) {
          byId[doc.id] = doc.data();
        }
        // Un échec du cache local ne doit jamais faire perdre le résultat
        // réseau : on l'ignore et on renvoie les données fraîches.
        try {
          await cache.cacheCollection(cacheBoxName, byId);
        } catch (_) {}
        return byId.entries.map((e) => fromMap(e.key, e.value)).toList();
      } catch (e) {
        debugPrint('[$collectionName] fetchAll a échoué : $e');
        // réseau indisponible : tombe au cache ci-dessous
      }
    }
    final cached = cache.readCollection(cacheBoxName);
    return cached.entries.map((e) => fromMap(e.key, e.value)).toList();
  }

  /// Flux temps réel (utilisé uniquement en ligne ; le provider bascule
  /// sur le cache dès que [ConnectivityProvider] signale une perte réseau).
  Stream<List<T>> watchAll({Query<Map<String, dynamic>>? customQuery}) {
    return (customQuery ?? _col).snapshots().map((snapshot) {
      final byId = <String, Map<String, dynamic>>{
        for (final doc in snapshot.docs) doc.id: doc.data(),
      };
      cache.cacheCollection(cacheBoxName, byId);
      return byId.entries.map((e) => fromMap(e.key, e.value)).toList();
    });
  }

  /// Création — en ligne : écrit directement ; hors-ligne : file d'attente
  /// + apparition immédiate dans le cache local (optimistic UI).
  Future<String> create(T item, {required bool isOnline, String? explicitId}) async {
    final id = explicitId ?? _uuid.v4();
    final data = toMap(item);

    if (isOnline) {
      try {
        await _col.doc(id).set(data);
        await cache.upsert(cacheBoxName, id, data);
        return id;
      } catch (e) {
        debugPrint('[$collectionName] create($id) a échoué : $e');
        // tombe à la file d'attente
      }
    }
    queue.enqueue(
      type: QueueActionType.create,
      collection: collectionName,
      payload: data,
      docId: id,
    );
    await cache.upsert(cacheBoxName, id, data);
    return id;
  }

  Future<void> update(String id, Map<String, dynamic> patch, {required bool isOnline}) async {
    if (isOnline) {
      try {
        await _col.doc(id).set(patch, SetOptions(merge: true));
        final existing = cache.readCollection(cacheBoxName)[id] ?? {};
        await cache.upsert(cacheBoxName, id, {...existing, ...patch});
        return;
      } catch (e) {
        debugPrint('[$collectionName] update($id) a échoué : $e');
        // tombe à la file d'attente
      }
    }
    queue.enqueue(
      type: QueueActionType.update,
      collection: collectionName,
      payload: patch,
      docId: id,
    );
    final existing = cache.readCollection(cacheBoxName)[id] ?? {};
    await cache.upsert(cacheBoxName, id, {...existing, ...patch});
  }

  Future<void> delete(String id, {required bool isOnline}) async {
    if (isOnline) {
      try {
        await _col.doc(id).delete();
        await cache.removeFromCache(cacheBoxName, id);
        return;
      } catch (e) {
        debugPrint('[$collectionName] delete($id) a échoué : $e');
        // tombe à la file d'attente
      }
    }
    queue.enqueue(
      type: QueueActionType.delete,
      collection: collectionName,
      payload: const {},
      docId: id,
    );
    await cache.removeFromCache(cacheBoxName, id);
  }
}
