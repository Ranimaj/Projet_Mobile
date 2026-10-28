import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';

import '../core/utils/offline_queue_service.dart';
import '../models/user_model.dart';
import 'storage_service.dart';

/// Envoi de la carte étudiant pour validation par un administrateur.
///
/// En ligne : upload puis écriture de `users/{uid}.studentCard`. Hors-ligne :
/// la photo est copiée dans le dossier de l'app et une action
/// `uploadStudentCard` est mise en file ; [OfflineQueueService.syncAll] fait
/// l'envoi au retour du réseau.
class StudentCardService {
  final StorageService _storage;
  final FirebaseFirestore _firestore;
  final OfflineQueueService _queue;
  final Directory Function()? _appDir;

  StudentCardService({
    required StorageService storage,
    required FirebaseFirestore firestore,
    required OfflineQueueService queue,
    Directory Function()? appDir,
  })  : _storage = storage,
        _firestore = firestore,
        _queue = queue,
        _appDir = appDir;

  Future<StudentCard> submit({
    required String uid,
    required File photo,
    required bool isOnline,
    DateTime Function()? now,
  }) async {
    final submittedAt = (now ?? DateTime.now)();
    final remotePath = 'student_cards/$uid/${submittedAt.millisecondsSinceEpoch}.jpg';

    if (isOnline) {
      final path = await _storage.uploadFile(photo, remotePath: remotePath);
      final card = StudentCard.pending(imagePath: path, submittedAt: submittedAt);
      // Remplacement complet (pas de merge) : un ancien motif de refus
      // serait conservé et l'écriture refusée par les règles Firestore.
      await _firestore.collection('users').doc(uid).update({'studentCard': card.toMap()});
      return card;
    }

    final dir = _appDir != null ? _appDir() : await getApplicationDocumentsDirectory();
    // Un fichier par envoi : une synchro en cours ne peut pas effacer la copie
    // d'un renvoi plus récent. Le payload ne garde que le nom relatif.
    final file = 'student_card_${uid}_${submittedAt.millisecondsSinceEpoch}.jpg';
    await photo.copy('${dir.path}/$file');
    final superseded = _queued(uid).toList();
    _queue.enqueue(
      type: QueueActionType.uploadStudentCard,
      collection: 'users',
      docId: uid,
      payload: {
        'uid': uid,
        'file': file,
        'remotePath': remotePath,
        'submittedAt': submittedAt.toIso8601String(),
      },
    );
    for (final old in superseded) {
      await _queue.deleteStudentCardFile(old);
    }
    return const StudentCard(status: StudentCardStatus.pending);
  }

  /// Une carte attend la connexion pour partir.
  bool hasQueuedSubmission(String uid) => _queued(uid).isNotEmpty;

  Iterable<QueuedAction> _queued(String uid) => _queue.pendingActions
      .where((a) => a.type == QueueActionType.uploadStudentCard && a.docId == uid);

  /// Déconnexion : abandonne l'envoi en attente de [uid] et ses fichiers.
  Future<void> discardQueued(String uid) => _queue.removeStudentCardActions(uid);
}
