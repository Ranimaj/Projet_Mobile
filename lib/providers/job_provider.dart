import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../models/job_offer_model.dart';
import '../services/local_repository.dart';
import '../services/local_store.dart';

/// Lecture des offres et candidatures pour l'accueil et le profil. Les
/// écritures et le suivi passent par `StageServices`.
class JobProvider extends ChangeNotifier {
  JobProvider({LocalStore? store})
      : _store = store ?? LocalStore(),
        _jobsRepo = LocalRepository<JobOfferModel>(
          collectionName: AppConstants.jobOffersCollection,
          fromMap: JobOfferModel.fromMap,
          toMap: (j) => j.toMap(),
          store: store,
        ),
        _applicationsRepo = LocalRepository<ApplicationModel>(
          collectionName: AppConstants.applicationsCollection,
          fromMap: ApplicationModel.fromMap,
          toMap: (a) => a.toMap(),
          store: store,
        );

  final LocalStore _store;
  final LocalRepository<JobOfferModel> _jobsRepo;
  final LocalRepository<ApplicationModel> _applicationsRepo;
  StreamSubscription<void>? _offersWatch;
  StreamSubscription<void>? _applicationsWatch;

  /// Sans effet : tout est local, le réseau ne change rien. Conservé pour
  /// le ChangeNotifierProxyProvider de main.dart.
  void updateConnectivity(bool online) {}

  List<JobOfferModel> _offers = [];
  List<ApplicationModel> _myApplications = [];
  String? _candidateId;
  bool isLoading = false;
  String? typeFilter; // 'stage' | 'emploi'

  List<JobOfferModel> get offers {
    var list = _offers.toList();
    if (typeFilter != null) {
      list = list.where((o) => o.type.name == typeFilter).toList();
    }
    list.sort((a, b) => b.postedAt.compareTo(a.postedAt));
    return list;
  }

  List<ApplicationModel> get myApplications => _myApplications;

  /// Matching intelligent : trie les offres par pertinence vis-à-vis des
  /// compétences du candidat (fonctionnalité avancée).
  List<JobOfferModel> recommendedFor(List<String> candidateSkills) {
    final scored = offers.map((o) => MapEntry(o, o.matchScore(candidateSkills))).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return scored.where((e) => e.value > 0).map((e) => e.key).toList();
  }

  void _readOffers() => _offers = _jobsRepo.fetchAll().where((o) => o.acceptsApplications).toList();

  void _readApplications() {
    final id = _candidateId;
    _myApplications = id == null
        ? []
        : (_applicationsRepo.fetchAll().where((a) => a.candidateId == id).toList()
          ..sort((a, b) => b.appliedAt.compareTo(a.appliedAt)));
  }

  Future<void> load() async {
    isLoading = true;
    notifyListeners();
    _readOffers();
    _offersWatch ??= _store.watch(AppConstants.jobOffersCollection).skip(1).listen((_) {
      _readOffers();
      notifyListeners();
    });
    isLoading = false;
    notifyListeners();
  }

  Future<void> loadMyApplications(String candidateId) async {
    _candidateId = candidateId;
    _readApplications();
    _applicationsWatch ??= _store.watch(AppConstants.applicationsCollection).skip(1).listen((_) {
      _readApplications();
      notifyListeners();
    });
    notifyListeners();
  }

  void setTypeFilter(String? type) {
    typeFilter = type;
    notifyListeners();
  }

  @override
  void dispose() {
    _offersWatch?.cancel();
    _applicationsWatch?.cancel();
    super.dispose();
  }
}
