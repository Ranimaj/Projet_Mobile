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
    final local = await photo.copy('${dir.path}/student_card_$uid.jpg');
    _queue.enqueue(
      type: QueueActionType.uploadStudentCard,
      collection: 'users',
      docId: uid,
      payload: {'localPath': local.path, 'remotePath': remotePath},
    );
    return const StudentCard(status: StudentCardStatus.pending);
  }

  /// Une carte attend la connexion pour partir.
  bool hasQueuedSubmission(String uid) => _queue.pendingActions
      .any((a) => a.type == QueueActionType.uploadStudentCard && a.docId == uid);
}
