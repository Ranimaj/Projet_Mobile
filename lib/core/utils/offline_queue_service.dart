import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants/app_constants.dart';

enum QueueActionType { create, update, delete }

/// Une action en attente de synchronisation (écrite hors-ligne).
class QueuedAction {
  final String id;
  final QueueActionType type;
  final String collection;
  final String docId;
  final Map<String, dynamic> payload;
  final DateTime queuedAt;

  QueuedAction({
    required this.id,
    required this.type,
    required this.collection,
    required this.docId,
    required this.payload,
    required this.queuedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'collection': collection,
        'docId': docId,
        'payload': payload,
        'queuedAt': queuedAt.toIso8601String(),
      };

  factory QueuedAction.fromJson(Map<dynamic, dynamic> json) {
    return QueuedAction(
      id: json['id'],
      type: QueueActionType.values.firstWhere((t) => t.name == json['type']),
      collection: json['collection'],
      docId: json['docId'],
      payload: Map<String, dynamic>.from(json['payload'] ?? {}),
      queuedAt: DateTime.parse(json['queuedAt']),
    );
  }
}

/// Cœur du mode hors-ligne (BNF3) : toute écriture faite sans réseau
/// (publier une annonce, postuler à une offre, s'inscrire à un événement…)
/// est stockée ici plutôt que perdue, puis rejouée vers Firestore dès que
/// [ConnectivityProvider] détecte un retour de connexion.
class OfflineQueueService {
  Box get _box => Hive.box(AppConstants.hiveOfflineQueueBox);
  static const _uuid = Uuid();

  /// Nombre d'actions en attente — affiché dans le bandeau "mode hors-ligne".
  int get pendingCount => _box.length;

  List<QueuedAction> get pendingActions =>
      _box.values.map((v) => QueuedAction.fromJson(v as Map)).toList();

  String enqueue({
    required QueueActionType type,
    required String collection,
    required Map<String, dynamic> payload,
    String? docId,
  }) {
    final id = _uuid.v4();
    final action = QueuedAction(
      id: id,
      type: type,
      collection: collection,
      docId: docId ?? id,
      payload: payload,
      queuedAt: DateTime.now(),
    );
    _box.put(id, action.toJson());
    return action.docId;
  }

  Future<void> remove(String actionId) async => _box.delete(actionId);

  /// Rejoue toutes les actions en attente contre Firestore, dans l'ordre
  /// chronologique. Appelé automatiquement au retour du réseau.
  Future<SyncResult> syncAll(FirebaseFirestore firestore) async {
    final actions = pendingActions..sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    int success = 0;
    int failed = 0;

    for (final action in actions) {
      try {
        final ref = firestore.collection(action.collection).doc(action.docId);
        switch (action.type) {
          case QueueActionType.create:
          case QueueActionType.update:
            await ref.set(action.payload, SetOptions(merge: true));
            break;
          case QueueActionType.delete:
            await ref.delete();
            break;
        }
        await remove(action.id);
        success++;
      } catch (_) {
        // On laisse l'action en file : elle sera retentée au prochain sync.
        failed++;
      }
    }
    return SyncResult(success: success, failed: failed);
  }
}

class SyncResult {
  final int success;
  final int failed;
  const SyncResult({required this.success, required this.failed});
}
