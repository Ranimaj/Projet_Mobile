import '../../core/constants/app_constants.dart';
import '../../models/event_model.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/local_store.dart';

/// La personne qui agit sur un événement : son uid et son rôle.
///
/// Les règles de rôle (seul l'organisateur ou un admin modifie, annule,
/// supprime, pointe ; chacun ne s'inscrit que lui-même) sont vérifiées par
/// EventProvider à partir de cette identité, et non de ce que l'écran lui
/// passe : elles tiennent même si l'écran est contourné.
class EventActor {
  final String uid;
  final bool isAdmin;

  const EventActor(this.uid, {this.isAdmin = false});

  /// Organisateur de [event] ou admin.
  bool canManage(EventModel event) => isAdmin || event.organizerId == uid;

  /// Session ouverte sur le téléphone, lue au même endroit que l'écran de
  /// connexion ([AuthService]) : uid de la session, compte existant, double
  /// authentification terminée, profil non désactivé. Sinon null (visiteur).
  static EventActor? fromStore(LocalStore store) {
    final uid = store.getValue(AuthService.sessionKey);
    if (uid == null || uid.isEmpty) return null;
    if (store.getValue(AuthService.twoFactorPendingKey) == '1') return null;
    if (store.get(AuthService.accountsCollection, uid) == null) return null;
    final profile = store.get(AppConstants.usersCollection, uid);
    final user = profile == null ? null : AppUser.fromMap(uid, profile);
    if (user?.disabled ?? false) return null;
    return EventActor(uid, isAdmin: user?.role == UserRole.admin);
  }

  @override
  String toString() => 'EventActor($uid${isAdmin ? ', admin' : ''})';
}
