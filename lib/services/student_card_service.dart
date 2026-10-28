import 'dart:async';
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

  /// Au-delà, l'envoi en ligne est abandonné au profit de la file : sur un
  /// réseau captif, `putFile` réessaie pendant 10 minutes.
  final Duration onlineTimeout;

  /// Codes Firebase qui signalent un problème de réseau (et non un refus).
  static const _networkCodes = {
    'unavailable',
    'network-request-failed',
    'retry-limit-exceeded',
    'deadline-exceeded',
  };

  StudentCardService({
    required StorageService storage,
    required FirebaseFirestore firestore,
    required OfflineQueueService queue,
    Directory Function()? appDir,
    this.onlineTimeout = const Duration(seconds: 20),
  })  : _storage = storage,
        _firestore = firestore,
        _queue = queue,
        _appDir = appDir;

  static bool _isNetworkError(Object e) =>
      e is TimeoutException ||
      e is SocketException ||
      (e is FirebaseException && _networkCodes.contains(e.code));

  Future<StudentCard> submit({
    required String uid,
    required File photo,
    required bool isOnline,
    DateTime Function()? now,
  }) async {
    final submittedAt = (now ?? DateTime.now)();
    final remotePath = 'student_cards/$uid/${submittedAt.millisecondsSinceEpoch}.jpg';

    if (isOnline) {
      var abandoned = false;
      Future<StudentCard> sendNow() async {
        final path = await _storage.uploadFile(photo, remotePath: remotePath);
        // Trop tard : la copie en file fera l'envoi, ne pas écrire deux fois.
        if (abandoned) throw TimeoutException('abandoned');
        final card = StudentCard.pending(imagePath: path, submittedAt: submittedAt);
        // Remplacement complet (pas de merge) : un ancien motif de refus
        // serait conservé et l'écriture refusée par les règles Firestore.
        await _firestore.collection('users').doc(uid).update({'studentCard': card.toMap()});
        return card;
      }

      try {
        return await sendNow().timeout(onlineTimeout);
      } catch (e) {
        if (!_isNetworkError(e)) rethrow;
        abandoned = true;
        // Réseau absent ou captif : bascule sur la file hors-ligne.
      }
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
