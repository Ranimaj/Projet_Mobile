import 'package:flutter/foundation.dart';
import 'dart:io';
import '../core/constants/app_constants.dart';
import '../models/job_offer_model.dart';
import '../services/local_repository.dart';
import '../services/local_store.dart';
import '../services/storage_service.dart';

/// Gestion Stage & Emploi — CRUD des offres + candidatures + matching
/// intelligent + suivi de statut (fonctionnalités avancées). Données
/// stockées sur le téléphone (SQLite), CV copiés dans le dossier de l'app.
class JobProvider extends ChangeNotifier {
  JobProvider({LocalStore? store, StorageService? storage})
      : _jobsRepo = LocalRepository<JobOfferModel>(
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
        ),
        _injectedStorage = storage;

  final LocalRepository<JobOfferModel> _jobsRepo;
  final LocalRepository<ApplicationModel> _applicationsRepo;
  final StorageService? _injectedStorage;
  StorageService? _storageInstance;
  StorageService get _storage => _storageInstance ??= _injectedStorage ?? StorageService();

  /// Sans effet : tout est local, le réseau ne change rien. Conservé pour
  /// le ChangeNotifierProxyProvider de main.dart.
  void updateConnectivity(bool online) {}

  List<JobOfferModel> _offers = [];
  List<ApplicationModel> _myApplications = [];
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

  Future<void> load() async {
    isLoading = true;
    notifyListeners();
    _offers = _jobsRepo.fetchAll();
    isLoading = false;
    notifyListeners();
  }

  Future<void> loadMyApplications(String candidateId) async {
    final all = _applicationsRepo.fetchAll();
    _myApplications = all.where((a) => a.candidateId == candidateId).toList()
      ..sort((a, b) => b.appliedAt.compareTo(a.appliedAt));
    notifyListeners();
  }

  void setTypeFilter(String? type) {
    typeFilter = type;
    notifyListeners();
  }

  Future<String> createOffer(JobOfferModel draft) async {
    final id = await _jobsRepo.create(draft);
    await load();
    return id;
  }

  /// Postuler à une offre — CV copié dans le dossier de l'app + lettre,
  /// création de la candidature. Fonctionne sans réseau (BF14).
  Future<String> applyToOffer({
    required JobOfferModel offer,
    required String candidateId,
    File? cvFile,
    String? coverLetter,
  }) async {
    String? cvUrl;
    if (cvFile != null) {
      cvUrl = await _storage.saveDocument(cvFile, folder: 'cv');
    }
    final application = ApplicationModel(
      id: '',
      jobOfferId: offer.id,
      jobTitle: offer.title,
      companyName: offer.companyName,
      candidateId: candidateId,
      cvUrl: cvUrl,
      coverLetter: coverLetter,
      appliedAt: DateTime.now(),
    );
    final id = await _applicationsRepo.create(application);
    await loadMyApplications(candidateId);
    return id;
  }

  /// Mise à jour du statut par le recruteur — visible aussitôt côté
  /// candidat (même base sur le téléphone).
  Future<void> updateApplicationStatus(String applicationId, ApplicationStatus status) async {
    await _applicationsRepo.update(applicationId, {'status': status.name});
  }
}
