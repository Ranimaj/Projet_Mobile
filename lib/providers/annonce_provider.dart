import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/offline_queue_service.dart';
import '../models/annonce_model.dart';
import '../models/user_model.dart';
import '../services/firestore_repository.dart';
import '../services/notification_service.dart';

/// Gestion des Annonces (campus) — CRUD complet, recherche + filtres,
/// épinglage automatique des annonces officielles, notifications push
/// ciblées par filière/année. Fonctionne hors-ligne (BNF3).
class AnnonceProvider extends ChangeNotifier {
  final _repo = FirestoreRepository<AnnonceModel>(
    collectionName: AppConstants.annoncesCollection,
    cacheBoxName: AppConstants.hiveAnnoncesBox,
    fromMap: AnnonceModel.fromMap,
    toMap: (a) => a.toMap(),
  );
  final _notifications = NotificationService();

  // ---------------------------------------------------------------------
  // Contexte (réseau + utilisateur), injecté par le ProxyProvider2 de main
  // ---------------------------------------------------------------------
  bool _isOnline = true;
  AppUser? _user;
  AppUser? get user => _user;

  void updateConnectivity(bool online) {
    final cameBack = online && !_isOnline;
    _isOnline = online;
    if (cameBack) {
      Future.microtask(() async {
        await _syncTopics();
        await _reloadWhenSynced();
      });
    }
  }

  void updateUser(AppUser? user) {
    final changed =
        user?.id != _user?.id || user?.major != _user?.major || user?.year != _user?.year;
    _user = user;
    if (changed) Future.microtask(_syncTopics);
  }

  // ---------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------
  bool get isAdmin => _user?.role == UserRole.admin;
  bool get isLoggedIn => _user != null;

  /// Cohérent avec firestore.rules : l'auteur modifie ses annonces
  /// (sauf "Officielle"), l'admin modifie tout.
  bool canEdit(AnnonceModel a) =>
      _user != null && (isAdmin || (a.authorId == _user!.id && !a.isOfficial));

  bool canDelete(AnnonceModel a) => _user != null && (isAdmin || a.authorId == _user!.id);

  bool canPin(AnnonceModel a) => isAdmin;

  // ---------------------------------------------------------------------
  // État / filtres
  // ---------------------------------------------------------------------
  List<AnnonceModel> _all = [];
  bool isLoading = false;

  /// Filtre par catégorie. La recherche et les autres filtres (urgentes,
  /// « pour moi », « mes annonces ») sont de l'état d'affichage : ils vivent
  /// dans l'écran (voir `AnnonceFilter`).
  String? categoryFilter;

  /// Épinglées en premier, puis date décroissante — priorisation automatique
  /// des annonces officielles (fonctionnalité avancée).
  List<AnnonceModel> get items {
    final result = categoryFilter == null
        ? _all.toList()
        : _all.where((a) => a.category == categoryFilter).toList();
    result.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return result;
  }

  /// Aperçu public (écran visiteur) : sans filtres.
  List<AnnonceModel> get publicPreview {
    final list = _all.toList()
      ..sort((a, b) {
        if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });
    return list.take(5).toList();
  }

  AnnonceModel? byId(String id) {
    for (final a in _all) {
      if (a.id == id) return a;
    }
    return null;
  }

  void setCategoryFilter(String? category) {
    categoryFilter = category;
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Lecture (Firestore -> cache Hive -> + actions hors-ligne en attente)
  // ---------------------------------------------------------------------
  Future<void> load() async {
    isLoading = true;
    notifyListeners();
    try {
      final fetched = await _repo.fetchAll(isOnline: _isOnline);
      _all = _applyPending(fetched);
    } catch (e) {
      debugPrint('Chargement des annonces impossible: $e');
    }
    isLoading = false;
    notifyListeners();
  }

  /// Rejoue localement les actions encore en file d'attente par-dessus la
  /// liste lue, pour qu'une annonce créée/modifiée/supprimée hors-ligne ne
  /// "disparaisse" pas tant qu'elle n'est pas synchronisée, et marque
  /// celles qui attendent la synchro ([AnnonceModel.pendingSync]).
  List<AnnonceModel> _applyPending(List<AnnonceModel> fetched) {
    final byId = {for (final a in fetched) a.id: a};
    final pendingIds = <String>{};

    final actions = _repo.queue.pendingActions
        .where((a) => a.collection == AppConstants.annoncesCollection)
        .toList()
      ..sort((a, b) => a.queuedAt.compareTo(b.queuedAt));

    for (final action in actions) {
      pendingIds.add(action.docId);
      switch (action.type) {
        case QueueActionType.create:
          byId[action.docId] = AnnonceModel.fromMap(action.docId, action.payload);
          break;
        case QueueActionType.update:
          final current = byId[action.docId];
          if (current != null) {
            byId[action.docId] =
                AnnonceModel.fromMap(action.docId, {...current.toMap(), ...action.payload});
          }
          break;
        case QueueActionType.delete:
          byId.remove(action.docId);
          break;
        default:
          break; // autres types de la file (ex. carte étudiante) : pas des annonces
      }
    }

    return byId.values
        .map((a) => pendingIds.contains(a.id) ? a.copyWith(pendingSync: true) : a)
        .toList();
  }

  /// Après un retour réseau, attend (max ~10 s) que la file soit rejouée
  /// par [ConnectivityProvider], puis recharge la liste.
  Future<void> _reloadWhenSynced() async {
    for (var i = 0; i < 10 && _repo.queue.pendingCount > 0; i++) {
      await Future.delayed(const Duration(seconds: 1));
    }
    await load();
  }

  // ---------------------------------------------------------------------
  // CRUD
  // ---------------------------------------------------------------------

  /// Création. Une annonce "Officielle" est épinglée automatiquement.
  /// La notification push ciblée est envoyée par la Cloud Function dès que
  /// le document existe côté serveur (donc aussi après une synchro hors-ligne).
  Future<String> createAnnonce(AnnonceModel draft) async {
    final toSave = draft.copyWith(isPinned: draft.isOfficial);
    final id = await _repo.create(toSave, isOnline: _isOnline);
    await load();
    return id;
  }

  Future<void> updateAnnonce(
    AnnonceModel original, {
    required String title,
    required String content,
    required String category,
    required bool isUrgent,
    required List<String> targetMajors,
    required List<String> targetYears,
    String? locationName,
    double? latitude,
    double? longitude,
  }) async {
    // Épinglage automatique si la catégorie devient / cesse d'être "Officielle".
    bool? pin;
    final becomesOfficial = category == 'Officielle';
    if (becomesOfficial && !original.isOfficial) pin = true;
    if (!becomesOfficial && original.isOfficial) pin = false;

    final now = DateTime.now();
    final updated = original.copyWith(
      targetMajors: targetMajors,
      targetYears: targetYears,
    );
    final patch = <String, dynamic>{
      'title': title,
      'content': content,
      'category': category,
      'isUrgent': isUrgent,
      // null = lieu effacé (Firestore stocke null, fromMap le relit en null).
      'locationName': locationName,
      'latitude': latitude,
      'longitude': longitude,
      'updatedAt': Timestamp.fromDate(now),
      ...updated.targetingMap(),
      if (pin != null) 'isPinned': pin,
    };
    await _repo.update(original.id, patch, isOnline: _isOnline);
    await load();
  }

  Future<void> pinAnnonce(String id, bool pinned) async {
    await _repo.update(id, {'isPinned': pinned}, isOnline: _isOnline);
    await load();
  }

  Future<void> deleteAnnonce(String id) async {
    await _repo.delete(id, isOnline: _isOnline);
    await load();
  }

  // ---------------------------------------------------------------------
  // Notifications push
  // ---------------------------------------------------------------------
  bool get pushEnabled => _notifications.pushEnabled;

  Future<void> setPushEnabled(bool value) async {
    await _notifications.setPushEnabled(value);
    notifyListeners();
    await _syncTopics();
  }

  Future<void> _syncTopics() async {
    if (!_isOnline) return;
    try {
      final u = _user;
      if (u == null) {
        await _notifications.clearTopics();
      } else {
        await _notifications.syncTopics(major: u.major, year: u.year);
      }
    } catch (e) {
      debugPrint('Synchronisation des topics impossible: $e');
    }
  }
}