import 'package:flutter/foundation.dart';
import 'dart:io';
import '../core/constants/app_constants.dart';
import '../models/job_offer_model.dart';
import '../services/firestore_repository.dart';
import '../services/storage_service.dart';

/// Gestion Stage & Emploi — CRUD des offres + candidatures + matching
/// intelligent + suivi de statut en temps réel (fonctionnalités avancées).
class JobProvider extends ChangeNotifier {
  final _jobsRepo = FirestoreRepository<JobOfferModel>(
    collectionName: AppConstants.jobOffersCollection,
    cacheBoxName: AppConstants.hiveJobsBox,
    fromMap: JobOfferModel.fromMap,
    toMap: (j) => j.toMap(),
  );
  final _applicationsRepo = FirestoreRepository<ApplicationModel>(
    collectionName: AppConstants.applicationsCollection,
    cacheBoxName: 'applications_box',
    fromMap: ApplicationModel.fromMap,
    toMap: (a) => a.toMap(),
  );
  final _storage = StorageService();

  bool _isOnline = true;
  void updateConnectivity(bool online) => _isOnline = online;

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
    _offers = await _jobsRepo.fetchAll(isOnline: _isOnline);
    isLoading = false;
    notifyListeners();
  }

  Future<void> loadMyApplications(String candidateId) async {
    final all = await _applicationsRepo.fetchAll(isOnline: _isOnline);
    _myApplications = all.where((a) => a.candidateId == candidateId).toList()
      ..sort((a, b) => b.appliedAt.compareTo(a.appliedAt));
    notifyListeners();
  }

  void setTypeFilter(String? type) {
    typeFilter = type;
    notifyListeners();
  }

  Future<String> createOffer(JobOfferModel draft) async {
    final id = await _jobsRepo.create(draft, isOnline: _isOnline);
    await load();
    return id;
  }

  /// Postuler à une offre — upload CV + lettre, création de la candidature.
  /// Fonctionne hors-ligne : la candidature est mise en file d'attente et
  /// envoyée dès le retour réseau (BF14).
  Future<String> applyToOffer({
    required JobOfferModel offer,
    required String candidateId,
    File? cvFile,
    String? coverLetter,
  }) async {
    String? cvUrl;
    if (_isOnline && cvFile != null) {
      cvUrl = await _storage.uploadDocument(cvFile, folder: 'cv');
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
    final id = await _applicationsRepo.create(application, isOnline: _isOnline);
    await loadMyApplications(candidateId);
    return id;
  }

  /// Mise à jour du statut par le recruteur — déclenche une notification
  /// de suivi en temps réel côté candidat (fonctionnalité avancée).
  Future<void> updateApplicationStatus(String applicationId, ApplicationStatus status) async {
    await _applicationsRepo.update(applicationId, {'status': status.name}, isOnline: _isOnline);
  }
}
