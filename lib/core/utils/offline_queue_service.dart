import 'dart:async';
import 'dart:io';

import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/user_model.dart';
import 'local_database.dart';

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
///
/// Les actions vivent dans le stockage SQLite partagé [LocalDatabase] : toutes
/// les instances de ce service voient la même file. Lectures synchrones
/// (mémoire), écritures enregistrées en arrière-plan, une par une.
class OfflineQueueService {
  /// Dossier documents de l'app, où vivent les copies locales des cartes.
  final Future<Directory> Function() _appDir;

  /// Synchro en cours, partagée par toutes les instances (la file l'est aussi) :
  /// une action n'est jamais rejouée deux fois en parallèle.
  static Future<SyncResult>? _running;

  OfflineQueueService({Future<Directory> Function()? appDir})
      : _appDir = appDir ?? getApplicationDocumentsDirectory;

  LocalDatabase get _store => LocalDatabase.instance;
  static const _uuid = Uuid();

  /// Nombre d'actions en attente — affiché dans le bandeau "mode hors-ligne".
  int get pendingCount => _store.queueLength;

  List<QueuedAction> get pendingActions => [for (final r in _store.queuedActions) _toAction(r)];

  static QueuedAction _toAction(QueueRecord r) => QueuedAction(
        id: r.id,
        type: QueueActionType.values.byName(r.type),
        collection: r.collection,
        docId: r.docId,
        payload: r.payload,
        queuedAt: r.queuedAt,
      );

  String enqueue({
    required QueueActionType type,
    required String collection,
    required Map<String, dynamic> payload,
    String? docId,
  }) {
    final id = _uuid.v4();
    // Un seul envoi de carte en attente par compte : le dernier remplace.
    final replacing = type == QueueActionType.uploadStudentCard && docId != null
        ? [
            for (final old in _store.queuedActions)
              if (old.type == type.name && old.docId == docId) old.id,
          ]
        : const <String>[];
    final action = QueuedAction(
      id: id,
      type: type,
      collection: collection,
      docId: docId ?? id,
      payload: Map<String, dynamic>.from(_storable(payload) as Map),
      queuedAt: DateTime.now(),
    );
    // Mémoire à jour tout de suite ; SQLite suit en arrière-plan.
    unawaited(_store.addQueued(
      id: action.id,
      type: action.type.name,
      collection: action.collection,
      docId: action.docId,
      payload: action.payload,
      queuedAt: action.queuedAt,
      replacing: replacing,
    ));
    return action.docId;
  }

  /// Un `Timestamp` Firestore est remplacé par un `DateTime` (stocké avec un
  /// marqueur de date, et que Firestore réécrit en `Timestamp` lors de la
  /// synchro), récursivement.
  static dynamic _storable(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is Map) {
      return <String, dynamic>{for (final e in value.entries) e.key.toString(): _storable(e.value)};
    }
    if (value is Iterable) return value.map(_storable).toList();
    return value;
  }

  Future<void> remove(String actionId) async => _store.removeQueued([actionId]);

  /// Fusionne [patch] dans les créations / mises à jour encore en file pour
  /// le document [collection]/[docId] (ex. remplacer des chemins de photos
  /// locales par leurs URL une fois envoyées), pour qu'un rejeu ultérieur
  /// n'écrase pas une valeur plus récente.
  ///
  /// Atomique vis-à-vis de [syncAll] : la mémoire est modifiée d'un bloc,
  /// sans attente, et une action modifiée pendant son envoi est renvoyée
  /// avant d'être retirée de la file.
  Future<void> patchPending(String collection, String docId, Map<String, dynamic> patch) async {
    // Tout ce qui suit jusqu'au `return` s'exécute sans attente.
    final extra = Map<String, dynamic>.from(_storable(patch) as Map);
    final updates = <String, Map<String, dynamic>>{
      for (final a in _store.queuedActions)
        if (a.collection == collection &&
            a.docId == docId &&
            (a.type == QueueActionType.create.name || a.type == QueueActionType.update.name))
          a.id: {...a.payload, ...extra},
    };
    return _store.updateQueuedPayloads(updates);
  }

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

  /// Ordre chronologique stable : à instant égal, l'ordre d'ajout est gardé.
  static List<QueuedAction> _chronological(List<QueuedAction> actions) {
    final indexed = actions.asMap().entries.toList()
      ..sort((a, b) {
        final byTime = a.value.queuedAt.compareTo(b.value.queuedAt);
        return byTime != 0 ? byTime : a.key.compareTo(b.key);
      });
    return [for (final e in indexed) e.value];
  }

  Future<SyncResult> _syncAll(
    FirebaseFirestore firestore,
    Future<String> Function(String localPath, String remotePath)? upload,
    String? currentUid,
  ) async {
    final actions = _chronological(pendingActions);
    int success = 0;
    int failed = 0;

    for (final action in actions) {
      // Retirée entre-temps (déconnexion…) : plus rien à rejouer.
      if (_store.queued(action.id) == null) continue;
      try {
        final ref = firestore.collection(action.collection).doc(action.docId);
        switch (action.type) {
          case QueueActionType.create:
          case QueueActionType.update:
            await _sendLatestThenRemove(action.id, ref);
            break;
          case QueueActionType.delete:
            await ref.delete();
            await remove(action.id);
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
            await remove(action.id);
            break;
        }
        success++;
      } catch (_) {
        // On laisse l'action en file : elle sera retentée au prochain sync.
        failed++;
      }
    }
    return SyncResult(success: success, failed: failed);
  }

  /// Envoie la version la plus récente de l'action [id] (merge), puis la
  /// retire. Si [patchPending] l'a modifiée pendant l'envoi, la nouvelle
  /// version est renvoyée d'abord (un merge rejoué est sans risque). Le
  /// contrôle de version et le retrait se font sans attente entre les deux :
  /// un patch ne peut jamais être perdu.
  Future<void> _sendLatestThenRemove(String id, DocumentReference<Map<String, dynamic>> ref) async {
    var current = _store.queued(id);
    while (current != null) {
      await ref.set(current.payload, SetOptions(merge: true));
      final after = _store.queued(id);
      if (after == null) return; // retirée pendant l'envoi
      if (after.revision == current.revision) {
        await _store.removeQueued([id]);
        return;
      }
      current = after;
    }
  }
}

class SyncResult {
  final int success;
  final int failed;
  const SyncResult({required this.success, required this.failed});
}
