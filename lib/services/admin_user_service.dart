import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_model.dart';
import 'storage_service.dart';

/// Accès Firestore de l'administration : liste des comptes, rôles,
/// désactivation et validation des cartes étudiant. Les règles Firestore
/// n'autorisent ces écritures qu'aux admins.
class AdminUserService {
  final FirebaseFirestore _db;
  StorageService? _storage;

  AdminUserService(FirebaseFirestore db, {StorageService? storage})
      : _db = db,
        _storage = storage;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  Stream<List<AppUser>> watchAll() =>
      _users.orderBy('createdAt', descending: true).snapshots().map((snap) =>
          [for (final d in snap.docs) AppUser.fromMap(d.id, d.data())]);

  Future<void> setRole(String uid, UserRole role) =>
      _users.doc(uid).update({'role': role.name});

  Future<void> setDisabled(String uid, bool disabled) =>
      _users.doc(uid).update({'disabled': disabled});

  /// Valide ou refuse la carte de [uid]. La carte existante est lue d'abord
  /// pour conserver `imagePath` et `submittedAt`, puis réécrite en entier.
  Future<void> reviewCard({
    required String uid,
    required bool approve,
    String? reason,
    required String reviewerUid,
    DateTime Function()? now,
  }) async {
    final snap = await _users.doc(uid).get();
    final current = snap.data()?['studentCard'];
    final existing = current is Map
        ? Map<String, dynamic>.from(current)
        : <String, dynamic>{};
    final card = <String, dynamic>{
      'status': approve ? 'verified' : 'rejected',
      if (existing['imagePath'] != null) 'imagePath': existing['imagePath'],
      if (existing['submittedAt'] != null)
        'submittedAt': existing['submittedAt'],
      'reviewedBy': reviewerUid,
      'reviewedAt': Timestamp.fromDate((now ?? DateTime.now)()),
      if (!approve && reason != null) 'rejectReason': reason,
    };
    await _users
        .doc(uid)
        .update({'studentCard': card, 'isVerifiedStudent': approve});
  }

  Future<String> cardImageUrl(String path) =>
      (_storage ??= StorageService()).downloadUrl(path);
}
