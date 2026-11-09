import '../core/constants/app_constants.dart';
import '../models/user_model.dart';
import 'auth_service.dart';
import 'local_store.dart';

/// Administration des comptes, sur la base locale ([LocalStore]) : liste des
/// comptes, rôles, désactivation, validation des cartes étudiant et
/// réinitialisation de mot de passe. Les écrans n'y donnent accès qu'aux
/// admins.
class AdminUserService {
  AdminUserService({LocalStore? store, AuthService? auth})
      : _store = store ?? LocalStore(),
        _injectedAuth = auth;

  final LocalStore _store;
  final AuthService? _injectedAuth;
  AuthService? _auth;
  AuthService get _authService =>
      _auth ??= _injectedAuth ?? AuthService(store: _store);

  static const String _users = AppConstants.usersCollection;

  /// Tous les comptes, plus récents d'abord ; les anciens profils sans
  /// `createdAt` sont rangés en dernier.
  Stream<List<AppUser>> watchAll() => _store.watch(_users).map((docs) {
        final entries = [
          for (final d in docs)
            (
              user: AppUser.fromMap(d.id, d.data),
              hasDate: d.data['createdAt'] != null
            ),
        ]..sort((a, b) {
            if (a.hasDate != b.hasDate) return a.hasDate ? -1 : 1;
            if (!a.hasDate) return 0;
            return b.user.createdAt.compareTo(a.user.createdAt);
          });
        return [for (final e in entries) e.user];
      });

  Future<void> setRole(String uid, UserRole role) =>
      _store.update(_users, uid, {'role': role.name});

  Future<void> setDisabled(String uid, bool disabled) =>
      _store.update(_users, uid, {'disabled': disabled});

  /// Valide ou refuse la carte de [uid]. La lecture et l'écriture se suivent
  /// sans `await` (atomique avec [LocalStore]) : si l'étudiant a renvoyé une
  /// autre photo depuis l'ouverture de l'écran (`imagePath` différent de
  /// [expectedImagePath]), rien n'est écrit et [AdminReviewConflict] est
  /// levée. `imagePath` et `submittedAt` sont conservés, la carte est
  /// réécrite en entier.
  Future<void> reviewCard({
    required String uid,
    required bool approve,
    String? reason,
    required String reviewerUid,
    required String? expectedImagePath,
    DateTime Function()? now,
  }) {
    final data = _store.get(_users, uid);
    if (data == null) return Future.error(DocumentNotFound(_users, uid));
    final current = data['studentCard'];
    final existing = current is Map
        ? Map<String, dynamic>.from(current)
        : <String, dynamic>{};
    if (existing['imagePath'] != expectedImagePath) {
      return Future.error(const AdminReviewConflict());
    }
    final card = <String, dynamic>{
      'status': approve ? 'verified' : 'rejected',
      if (existing['imagePath'] != null) 'imagePath': existing['imagePath'],
      if (existing['submittedAt'] != null)
        'submittedAt': existing['submittedAt'],
      'reviewedBy': reviewerUid,
      'reviewedAt': (now ?? DateTime.now)(),
      if (!approve && reason != null) 'rejectReason': reason,
    };
    return _store
        .update(_users, uid, {'studentCard': card, 'isVerifiedStudent': approve});
  }

  /// Remplace le mot de passe du compte [uid] par un mot de passe
  /// temporaire, renvoyé pour être transmis à l'utilisateur (pas d'email
  /// sans serveur).
  Future<String> resetPassword(String uid) =>
      _authService.resetPasswordByAdmin(uid);
}

/// La carte a été renvoyée (autre photo) pendant que l'admin la regardait.
class AdminReviewConflict implements Exception {
  const AdminReviewConflict();

  String get message => 'La carte a changé, rouvre-la';

  @override
  String toString() => message;
}
