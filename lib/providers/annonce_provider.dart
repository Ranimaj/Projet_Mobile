import 'package:flutter/foundation.dart';
import '../models/annonce_model.dart';
import '../models/user_model.dart';
import '../services/notification_service.dart';
import '../services/sqlite/annonce_store.dart';
import '../services/sqlite/local_annonce_repository.dart';

/// Gestion des Annonces (campus) — CRUD complet, recherche + filtres,
/// épinglage automatique des annonces officielles, notifications push
/// ciblées par filière/année. Les données vivent dans la table SQLite
/// `annonces` : l'app fonctionne donc entièrement hors-ligne (BNF3).
class AnnonceProvider extends ChangeNotifier {
  /// [repository] est injectable pour les tests (dépôt en mémoire).
  AnnonceProvider({AnnonceStore? repository}) : _repoOverride = repository;

  final AnnonceStore? _repoOverride;

  // Créé à la première utilisation : les tests injectent une doublure.
  late final AnnonceStore _repo = _repoOverride ?? LocalAnnonceRepository();
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
    if (cameBack) Future.microtask(_syncTopics);
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
  // Lecture (SQLite)
  // ---------------------------------------------------------------------
  Future<void> load() async {
    isLoading = true;
    notifyListeners();
    try {
      _all = await _repo.fetchAll();
    } catch (e) {
      debugPrint('Chargement des annonces impossible: $e');
    }
    isLoading = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // CRUD
  // ---------------------------------------------------------------------

  /// Création. Une annonce "Officielle" est épinglée automatiquement.
  /// Le ciblage (filières / années) est enregistré avec l'annonce ; les
  /// abonnements push par topic restent gérés par [NotificationService].
  Future<String> createAnnonce(AnnonceModel draft) async {
    final toSave = draft.copyWith(isPinned: draft.isOfficial);
    final id = await _repo.create(toSave);
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

    final updated = original.edited(
      title: title,
      content: content,
      category: category,
      isUrgent: isUrgent,
      targetMajors: targetMajors,
      targetYears: targetYears,
      // null = lieu effacé.
      locationName: locationName,
      latitude: latitude,
      longitude: longitude,
      updatedAt: DateTime.now(),
      isPinned: pin,
    );
    await _repo.update(updated);
    await load();
  }

  Future<void> pinAnnonce(String id, bool pinned) async {
    final current = byId(id) ?? await _repo.byId(id);
    if (current == null) return;
    await _repo.update(current.copyWith(isPinned: pinned));
    await load();
  }

  Future<void> deleteAnnonce(String id) async {
    await _repo.delete(id);
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
