import '../../core/constants/app_constants.dart';
import '../../models/job_offer_model.dart';
import '../local_store.dart';
import 'cv_storage.dart';
import 'db_changes.dart';

/// CRUD des offres de stage et d'emploi.
class JobRepository {
  JobRepository(this._store, this._changes, this._cvs);

  final LocalStore _store;
  final DbChanges _changes;
  final CvStorage _cvs;

  static const _jobs = AppConstants.jobOffersCollection;
  static const _applications = AppConstants.applicationsCollection;

  JobOfferModel _read(String id, Map<String, dynamic> data, Map<String, int> counts) =>
      JobOfferModel.fromMap(id, data, applicantCount: counts[id] ?? 0);

  Map<String, int> _counts() {
    final counts = <String, int>{};
    for (final a in _store.all(_applications)) {
      final jobId = a.data['jobOfferId'] as String?;
      if (jobId != null) counts[jobId] = (counts[jobId] ?? 0) + 1;
    }
    return counts;
  }

  List<JobOfferModel> _list(bool Function(JobOfferModel) test) {
    final counts = _counts();
    return [
      for (final d in _store.all(_jobs))
        if (test(_read(d.id, d.data, counts))) _read(d.id, d.data, counts),
    ]..sort((a, b) => b.postedAt.compareTo(a.postedAt));
  }

  Future<JobOfferModel> save({
    String? id,
    required String recruiterId,
    required String title,
    required String company,
    required JobType type,
    required String location,
    String duration = '',
    required String description,
    String requirements = '',
    List<String> skills = const [],
    DateTime? deadline,
    bool isOpen = true,
  }) async {
    final jobId = id ?? LocalStore.newId();
    final postedAt = id == null ? DateTime.now() : parseDate(_store.get(_jobs, jobId)?['postedAt']) ?? DateTime.now();
    final job = JobOfferModel(
      id: jobId,
      recruiterId: recruiterId,
      companyName: company.trim(),
      title: title.trim(),
      description: description.trim(),
      type: type,
      location: location.trim(),
      duration: duration.trim(),
      requirements: requirements.trim(),
      requiredSkills: [for (final s in skills) if (s.trim().isNotEmpty) s.trim()],
      postedAt: postedAt,
      deadline: deadline,
      isOpen: isOpen,
    );
    final writes = [_store.set(_jobs, jobId, job.toMap())];
    if (id != null) {
      // Les candidatures gardent l'intitulé affiché et utilisé dans les emails.
      for (final a in _store.where(_applications, (d) => d['jobOfferId'] == jobId)) {
        writes.add(_store.merge(_applications, a.id, {'jobTitle': job.title, 'companyName': job.companyName}));
      }
    }
    await Future.wait(writes);
    _changes.bump();
    return (await byId(jobId))!;
  }

  Future<JobOfferModel?> byId(String id) async {
    final data = _store.get(_jobs, id);
    return data == null ? null : _read(id, data, _counts());
  }

  /// Offres visibles par les étudiants : ouvertes et non expirées.
  Future<List<JobOfferModel>> open() async => _list((j) => j.acceptsApplications);

  Future<List<JobOfferModel>> byRecruiter(String recruiterId) async => _list((j) => j.recruiterId == recruiterId);

  Future<List<JobOfferModel>> all() async => _list((_) => true);

  Future<void> setOpen(String id, bool open) async {
    await _store.update(_jobs, id, {'isOpen': open});
    _changes.bump();
  }

  /// Supprime l'offre, ses candidatures, ses scores et les CV associés.
  Future<void> delete(String id) async {
    final doomed = _store.where(_applications, (d) => d['jobOfferId'] == id);
    await Future.wait([
      _store.delete(_jobs, id),
      _store.deleteWhere(_applications, (d) => d['jobOfferId'] == id),
      _store.deleteWhere(AppConstants.stageMatchScoresCollection, (d) => d['jobId'] == id),
    ]);
    for (final a in doomed) {
      final path = a.data['cvUrl'] as String?;
      if (path != null) await _cvs.delete(path);
    }
    _changes.bump();
  }
}
