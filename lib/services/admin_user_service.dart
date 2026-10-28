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

  /// Tous les comptes, plus récents d'abord. Pas d'`orderBy` côté serveur :
  /// il écarterait les anciens profils sans `createdAt`, triés ici en
  /// dernier.
  Stream<List<AppUser>> watchAll() => _users.snapshots().map((snap) {
        final entries = [
          for (final d in snap.docs)
            (user: AppUser.fromMap(d.id, d.data()), hasDate: d.data()['createdAt'] != null),
        ]..sort((a, b) {
            if (a.hasDate != b.hasDate) return a.hasDate ? -1 : 1;
            if (!a.hasDate) return 0;
            return b.user.createdAt.compareTo(a.user.createdAt);
          });
        return [for (final e in entries) e.user];
      });

  Future<void> setRole(String uid, UserRole role) =>
      _users.doc(uid).update({'role': role.name});

  Future<void> setDisabled(String uid, bool disabled) =>
      _users.doc(uid).update({'disabled': disabled});

  /// Valide ou refuse la carte de [uid]. La lecture et l'écriture se font
  /// dans une transaction : si l'étudiant a renvoyé une autre photo depuis
  /// l'ouverture de l'écran (`imagePath` différent de [expectedImagePath]),
  /// rien n'est écrit et [AdminReviewConflict] est levée. `imagePath` et
  /// `submittedAt` sont conservés, la carte est réécrite en entier.
  Future<void> reviewCard({
    required String uid,
    required bool approve,
    String? reason,
    required String reviewerUid,
    required String? expectedImagePath,
    DateTime Function()? now,
  }) {
    final ref = _users.doc(uid);
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final current = snap.data()?['studentCard'];
      final existing = current is Map
          ? Map<String, dynamic>.from(current)
          : <String, dynamic>{};
      if (existing['imagePath'] != expectedImagePath) {
        throw const AdminReviewConflict();
      }
      final card = <String, dynamic>{
        'status': approve ? 'verified' : 'rejected',
        if (existing['imagePath'] != null) 'imagePath': existing['imagePath'],
        if (existing['submittedAt'] != null)
          'submittedAt': existing['submittedAt'],
        'reviewedBy': reviewerUid,
        'reviewedAt': Timestamp.fromDate((now ?? DateTime.now)()),
        if (!approve && reason != null) 'rejectReason': reason,
      };
      tx.update(ref, {'studentCard': card, 'isVerifiedStudent': approve});
    });
  }

  Future<String> cardImageUrl(String path) =>
      (_storage ??= StorageService()).downloadUrl(path);
}

/// La carte a été renvoyée (autre photo) pendant que l'admin la regardait.
class AdminReviewConflict implements Exception {
  const AdminReviewConflict();

  String get message => 'La carte a changé, rouvre-la';

  @override
  String toString() => message;
}
