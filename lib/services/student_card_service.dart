import 'dart:io';

import '../core/constants/app_constants.dart';
import '../models/user_model.dart';
import 'local_store.dart';
import 'storage_service.dart';

/// Envoi de la carte étudiant pour validation par un administrateur : la
/// photo est copiée dans le dossier de l'app et `users/{uid}.studentCard`
/// passe « en attente ».
class StudentCardService {
  StudentCardService({required StorageService storage, LocalStore? store})
      : _storage = storage,
        _store = store ?? LocalStore();

  final StorageService _storage;
  final LocalStore _store;

  Future<StudentCard> submit({
    required String uid,
    required File photo,
    DateTime Function()? now,
  }) async {
    final submittedAt = (now ?? DateTime.now)();
    final profile = _store.get(AppConstants.usersCollection, uid);
    if (profile == null) throw DocumentNotFound(AppConstants.usersCollection, uid);
    final previous = profile['studentCard'];
    final path = await _storage.saveFile(
      photo,
      relativePath: 'student_cards/$uid/${submittedAt.millisecondsSinceEpoch}.jpg',
    );
    final card = StudentCard.pending(imagePath: path, submittedAt: submittedAt);
    // Remplacement complet : un ancien motif de refus ne doit pas rester.
    await _store.update(AppConstants.usersCollection, uid, {'studentCard': card.toMap()});
    if (previous is Map && previous['imagePath'] != path) {
      await _storage.delete(previous['imagePath'] as String?);
    }
    return card;
  }
}
