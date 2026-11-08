import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/local_cache_service.dart';
import '../../core/utils/offline_queue_service.dart';
import '../../models/article_model.dart';
import '../firestore_repository.dart';
import 'article_database.dart';

/// Dépôt des articles de Vente & Don avec **SQLite comme base principale**.
///
///  - Lecture : l'app lit toujours la base SQLite du téléphone. En ligne, les
///    articles des autres étudiants sont d'abord récupérés sur Firebase et
///    enregistrés dans SQLite.
///  - Écriture : chaque création / modification / suppression est écrite
///    d'abord dans SQLite (marquée « en attente »), puis envoyée à Firebase.
///    Sans réseau, l'envoi passe par [OfflineQueueService] et la ligne reste
///    « en attente » jusqu'à la synchronisation.
///
/// Remplace, pour les articles, le cache Hive générique de
/// [FirestoreRepository] (même interface, donc le provider ne change pas).
class SqliteArticleRepository implements FirestoreRepository<ArticleModel> {
  SqliteArticleRepository({
    Future<ArticleDatabase> Function()? openDatabase,
    FirebaseFirestore? firestore,
    OfflineQueueService? queue,
  })  : _openDatabase = openDatabase ?? ArticleDatabase.open,
        _firestoreOverride = firestore,
        _queueOverride = queue;

  final Future<ArticleDatabase> Function() _openDatabase;
  final FirebaseFirestore? _firestoreOverride;
  final OfflineQueueService? _queueOverride;
  static const _uuid = Uuid();

  late final Future<ArticleDatabase> _db = _openDatabase();
  late final FirebaseFirestore _firestore = _firestoreOverride ?? FirebaseFirestore.instance;

  /// Base SQLite ouverte (pour les écrans de diagnostic et les tests).
  Future<ArticleDatabase> get database => _db;

  @override
  late final OfflineQueueService queue = _queueOverride ?? OfflineQueueService();

  /// Non utilisé pour les articles (SQLite le remplace) ; gardé pour
  /// respecter l'interface de [FirestoreRepository].
  @override
  late final LocalCacheService cache = LocalCacheService();

  @override
  final String collectionName = AppConstants.articlesCollection;

  @override
  final String cacheBoxName = AppConstants.hiveArticlesBox;

  @override
  final ArticleModel Function(String id, Map<String, dynamic> map) fromMap = ArticleModel.fromMap;

  @override
  final Map<String, dynamic> Function(ArticleModel item) toMap = _toMap;

  static Map<String, dynamic> _toMap(ArticleModel a) => a.toMap();

  CollectionReference<Map<String, dynamic>> get _col => _firestore.collection(collectionName);

  /// Ids d'articles qui ont encore une action en file d'attente.
  Set<String> _queuedIds() {
    try {
      return {
        for (final a in queue.pendingActions)
          if (a.collection == collectionName) a.docId,
      };
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<List<ArticleModel>> fetchAll({Query<Map<String, dynamic>>? customQuery, required bool isOnline}) async {
    final db = await _db;
    if (isOnline) {
      try {
        final snapshot = await (customQuery ?? _col).get();
        final remote = [for (final d in snapshot.docs) ArticleModel.fromMap(d.id, d.data())];
        // Garde la version du téléphone pour ce qui n'est pas encore parti.
        final keep = (await db.unsyncedIds()).intersection(_queuedIds());
        await db.replaceWithRemote(remote, keepLocal: keep);
      } catch (_) {
        // Pas de réseau ou Firebase injoignable : on lit SQLite ci-dessous.
      }
    }
    return db.all();
  }

  @override
  Stream<List<ArticleModel>> watchAll({Query<Map<String, dynamic>>? customQuery}) =>
      Stream.fromFuture(fetchAll(customQuery: customQuery, isOnline: true));

  @override
  Future<String> create(ArticleModel item, {required bool isOnline, String? explicitId}) async {
    final id = explicitId ?? _uuid.v4();
    final data = item.toMap();
    final db = await _db;
    await db.upsert(ArticleModel.fromMap(id, data), state: SyncState.pending);
    if (isOnline) {
      try {
        await _col.doc(id).set(data);
        await db.markSynced(id);
        return id;
      } catch (_) {
        // envoi plus tard
      }
    }
    queue.enqueue(type: QueueActionType.create, collection: collectionName, payload: data, docId: id);
    return id;
  }

  @override
  Future<void> update(String id, Map<String, dynamic> patch, {required bool isOnline}) async {
    final db = await _db;
    await db.patch(id, patch, state: SyncState.pending);
    if (isOnline) {
      try {
        await _col.doc(id).set(patch, SetOptions(merge: true));
        await db.markSynced(id);
        return;
      } catch (_) {
        // envoi plus tard
      }
    }
    queue.enqueue(type: QueueActionType.update, collection: collectionName, payload: patch, docId: id);
  }

  @override
  Future<void> delete(String id, {required bool isOnline}) async {
    final db = await _db;
    await db.remove(id, pending: true);
    if (isOnline) {
      try {
        await _col.doc(id).delete();
        await db.remove(id);
        return;
      } catch (_) {
        // envoi plus tard
      }
    }
    queue.enqueue(type: QueueActionType.delete, collection: collectionName, payload: const {}, docId: id);
  }
}
