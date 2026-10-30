import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/user_model.dart';
import '../constants/app_constants.dart';
import 'firestore_codec.dart';

enum QueueActionType {
  create,
  update,
  delete,

  /// Carte étudiant prise hors-ligne : payload `{uid, file, remotePath,
  /// submittedAt}` où `file` est un nom de fichier relatif au dossier
  /// documents de l'app (le chemin absolu change après une mise à jour iOS).
  uploadStudentCard,
}

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
        'payload': FirestoreCodec.encodeMap(payload),
        'queuedAt': queuedAt.toIso8601String(),
      };

  factory QueuedAction.fromJson(Map<dynamic, dynamic> json) {
    return QueuedAction(
      id: json['id'],
      type: QueueActionType.values.firstWhere((t) => t.name == json['type']),
      collection: json['collection'],
      docId: json['docId'],
      payload: FirestoreCodec.decodeMap(json['payload'] as Map? ?? {}),
      queuedAt: DateTime.parse(json['queuedAt']),
    );
  }
}

/// Cœur du mode hors-ligne (BNF3) : toute écriture faite sans réseau
/// (publier une annonce, postuler à une offre, s'inscrire à un événement…)
/// est stockée ici plutôt que perdue, puis rejouée vers Firestore dès que
/// [ConnectivityProvider] détecte un retour de connexion.
class OfflineQueueService {
  /// Dossier documents de l'app, où vivent les copies locales des cartes.
  final Future<Directory> Function() _appDir;
  Future<SyncResult>? _running;

  OfflineQueueService({Future<Directory> Function()? appDir})
      : _appDir = appDir ?? getApplicationDocumentsDirectory;

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
    if (type == QueueActionType.uploadStudentCard && docId != null) {
      // Un seul envoi de carte en attente par compte : le dernier remplace.
      for (final old in pendingActions) {
        if (old.type == type && old.docId == docId) _box.delete(old.id);
      }
    }
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

  /// Chemin absolu de la copie locale d'une action `uploadStudentCard`.
  Future<String> localPathOf(QueuedAction action) async =>
      '${(await _appDir()).path}/${action.payload['file']}';

  /// Supprime la copie locale de [action] (sans effet si déjà absente).
  Future<void> deleteStudentCardFile(QueuedAction action) async {
    try {
      final file = File(await localPathOf(action));
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Retire les envois de carte de [uid] (déconnexion) et leurs copies locales.
  Future<void> removeStudentCardActions(String uid) async {
    for (final a in pendingActions) {
      if (a.type == QueueActionType.uploadStudentCard && a.docId == uid) {
        await remove(a.id);
        await deleteStudentCardFile(a);
      }
    }
  }

  /// Rejoue toutes les actions en attente contre Firestore, dans l'ordre
  /// chronologique. Appelé automatiquement au retour du réseau. Un appel
  /// pendant qu'une synchro tourne renvoie la synchro en cours.
  ///
  /// [currentUid] : si fourni, les envois de carte d'un autre compte restent
  /// en file (les règles refuseraient l'écriture sur le document d'autrui).
  Future<SyncResult> syncAll(
    FirebaseFirestore firestore, {
    Future<String> Function(String localPath, String remotePath)? upload,
    String? currentUid,
  }) {
    final running = _running;
    if (running != null) return running;
    return _running = _syncAll(firestore, upload, currentUid).whenComplete(() => _running = null);
  }

  Future<SyncResult> _syncAll(
    FirebaseFirestore firestore,
    Future<String> Function(String localPath, String remotePath)? upload,
    String? currentUid,
  ) async {
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
          case QueueActionType.uploadStudentCard:
            final owner = action.payload['uid'] ?? action.docId;
            if (currentUid != null && owner != currentUid) continue;
            if (upload == null) throw StateError('no uploader');
            final localPath = await localPathOf(action);
            if (!await File(localPath).exists()) {
              // Fichier perdu : inutile de réessayer indéfiniment.
              await remove(action.id);
              continue;
            }
            final remotePath = action.payload['remotePath'] as String;
            await upload(localPath, remotePath);
            final submitted =
                DateTime.tryParse('${action.payload['submittedAt']}') ?? DateTime.now();
            // Remplacement complet de la carte : un merge garderait un ancien
            // motif de refus que les règles Firestore interdisent.
            await ref.update({
              'studentCard':
                  StudentCard.pending(imagePath: remotePath, submittedAt: submitted).toMap(),
            });
            await deleteStudentCardFile(action);
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
