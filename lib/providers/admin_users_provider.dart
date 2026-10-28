import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../models/user_model.dart';
import '../services/admin_user_service.dart';

/// État de l'écran d'administration des comptes : flux temps réel des
/// utilisateurs, recherche (anti-rebond), filtres et actions admin.
class AdminUsersProvider extends ChangeNotifier {
  final AdminUserService _service;
  final String currentAdminUid;
  final Duration _debounce;
  StreamSubscription<List<AppUser>>? _sub;
  Timer? _timer;

  List<AppUser> users = const [];
  bool isLoading = true;
  String? error;
  String query = '';
  UserRole? roleFilter;
  StudentCardStatus? cardFilter;

  AdminUsersProvider(
    this._service, {
    required this.currentAdminUid,
    Duration? debounce,
  }) : _debounce = debounce ?? AppConstants.debounceDuration {
    _sub = _service.watchAll().listen((list) {
      users = list;
      isLoading = false;
      error = null;
      notifyListeners();
    }, onError: (Object _) {
      isLoading = false;
      error = 'Impossible de charger les utilisateurs.';
      notifyListeners();
    });
  }

  List<AppUser> get filtered {
    final q = query.trim().toLowerCase();
    return [
      for (final u in users)
        if ((roleFilter == null || u.role == roleFilter) &&
            (cardFilter == null || u.studentCard.status == cardFilter) &&
            (q.isEmpty ||
                u.fullName.toLowerCase().contains(q) ||
                u.email.toLowerCase().contains(q)))
          u,
    ];
  }

  int get adminCount => users.where((u) => u.role == UserRole.admin).length;

  /// Le dernier admin ne peut pas se rétrograder lui-même.
  bool canChangeRole(AppUser u, UserRole to) =>
      !(u.id == currentAdminUid && to != UserRole.admin && adminCount <= 1);

  void setQuery(String value) {
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      query = value;
      notifyListeners();
    });
  }

  void setRoleFilter(UserRole? role) {
    roleFilter = role;
    notifyListeners();
  }

  void setCardFilter(StudentCardStatus? status) {
    cardFilter = status;
    notifyListeners();
  }

  Future<bool> changeRole(AppUser user, UserRole to) {
    if (!canChangeRole(user, to)) return Future.value(false);
    return _run(() => _service.setRole(user.id, to));
  }

  Future<bool> setDisabled(AppUser user, bool disabled) =>
      _run(() => _service.setDisabled(user.id, disabled));

  Future<bool> reviewCard(AppUser user,
          {required bool approve, String? reason}) =>
      _run(() => _service.reviewCard(
            uid: user.id,
            approve: approve,
            reason: reason,
            reviewerUid: currentAdminUid,
          ));

  Future<String> cardImageUrl(String path) => _service.cardImageUrl(path);

  Future<bool> _run(Future<void> Function() action) async {
    try {
      await action();
      return true;
    } catch (_) {
      error = 'Action impossible. Vérifie ta connexion et tes droits.';
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
