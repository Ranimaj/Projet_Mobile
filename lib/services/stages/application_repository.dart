import '../../core/constants/app_constants.dart';
import '../../models/job_offer_model.dart';
import '../../models/stage_records.dart';
import '../../models/user_model.dart';
import '../local_store.dart';
import 'cv_storage.dart';
import 'db_changes.dart';
import 'email_service.dart';

class AlreadyAppliedException implements Exception {
  @override
  String toString() => 'Vous avez déjà postulé à cette offre.';
}

class JobClosedException implements Exception {
  @override
  String toString() => 'Cette offre n\'accepte plus de candidatures.';
}

class InvalidTransitionException implements Exception {
  @override
  String toString() => 'Ce changement d\'étape n\'est pas autorisé.';
}

class ApplicationLockedException implements Exception {
  @override
  String toString() => 'La candidature ne peut plus être modifiée : le recruteur l\'a déjà traitée.';
}

/// Candidatures et suivi : chaque étape ajoute un évènement et un email à envoyer.
class ApplicationRepository {
  ApplicationRepository(this._store, this._changes, this._cvs, this._emails);

  final LocalStore _store;
  final DbChanges _changes;
  final CvStorage _cvs;
  final EmailService _emails;

  static const _applications = AppConstants.applicationsCollection;
  static const _jobs = AppConstants.jobOffersCollection;

  /// Un étudiant n'a qu'une candidature par offre : l'identifiant le garantit.
  static String docId(String jobId, String studentId) => '${jobId}_$studentId';

  Future<ApplicationModel> apply({
    required String jobId,
    required AppUser student,
    required PickedCv cv,
    required String motivationLetter,
    required String message,
  }) async {
    _requireOpen(jobId);
    final id = docId(jobId, student.id);
    if (_store.exists(_applications, id)) throw AlreadyAppliedException();

    final cvPath = await _cvs.store(cv);
    // La copie du CV a rendu la main : on revérifie avant d'écrire.
    try {
      final job = _requireOpen(jobId);
      if (_store.exists(_applications, id)) throw AlreadyAppliedException();
      final now = DateTime.now();
      final application = ApplicationModel(
        id: id,
        jobOfferId: jobId,
        jobTitle: job.title,
        companyName: job.companyName,
        candidateId: student.id,
        studentName: student.fullName,
        studentEmail: student.email,
        cvUrl: cvPath,
        cvName: cv.name,
        coverLetter: motivationLetter.trim(),
        message: message.trim(),
        appliedAt: now,
        history: [ApplicationEvent(status: ApplicationStatus.pending, createdAt: now)],
      );
      await Future.wait([
        _store.set(_applications, id, application.toMap()),
        _emails.enqueue(application, ApplicationStatus.pending, ''),
      ]);
      _changes.bump();
      await _emails.flush();
      return application;
    } catch (_) {
      await _cvs.delete(cvPath);
      rethrow;
    }
  }

  JobOfferModel _requireOpen(String jobId) {
    final data = _store.get(_jobs, jobId);
    final job = data == null ? null : JobOfferModel.fromMap(jobId, data);
    if (job == null || !job.acceptsApplications) throw JobClosedException();
    return job;
  }

  /// Modifiable par l'étudiant tant que la candidature est en attente.
  Future<void> edit(
    String id, {
    required String studentId,
    PickedCv? newCv,
    required String motivationLetter,
    required String message,
  }) async {
    final current = _owned(id, studentId);
    final newPath = newCv == null ? null : await _cvs.store(newCv);
    _owned(id, studentId);
    await _store.update(_applications, id, {
      'coverLetter': motivationLetter.trim(),
      'message': message.trim(),
      'updatedAt': DateTime.now(),
      if (newCv != null) 'cvUrl': newPath,
      if (newCv != null) 'cvName': newCv.name,
    });
    final oldPath = current.cvUrl;
    if (newCv != null && oldPath != null) await _cvs.delete(oldPath);
    _changes.bump();
  }

  /// Retrait par l'étudiant, uniquement tant qu'elle est en attente.
  Future<void> withdraw(String id, String studentId) async {
    final current = _owned(id, studentId);
    await _store.delete(_applications, id);
    final path = current.cvUrl;
    if (path != null) await _cvs.delete(path);
    _changes.bump();
  }

  ApplicationModel _owned(String id, String studentId) {
    final data = _store.get(_applications, id);
    final current = data == null ? null : ApplicationModel.fromMap(id, data);
    if (current == null || current.candidateId != studentId || current.status != ApplicationStatus.pending) {
      throw ApplicationLockedException();
    }
    return current;
  }

  /// Fait avancer la candidature ; renvoie l'état de l'email de cette étape.
  ///
  /// Le changement est enregistré même si l'envoi échoue : l'email reste dans
  /// la file et repart au prochain essai. Pas d'`await` entre la lecture et les
  /// écritures : deux appuis rapides ne peuvent pas franchir deux étapes.
  Future<EmailStatus> moveTo(String id, ApplicationStatus target, {required String recruiterId, String note = ''}) async {
    final data = _store.get(_applications, id);
    if (data == null) throw InvalidTransitionException();
    final application = ApplicationModel.fromMap(id, data);
    if (_store.get(_jobs, application.jobOfferId)?['recruiterId'] != recruiterId) throw InvalidTransitionException();
    if (!application.status.canMoveTo(target)) throw InvalidTransitionException();

    final now = DateTime.now();
    final cleanNote = note.trim();
    final write = _store.update(_applications, id, {
      'status': target.name,
      'updatedAt': now,
      'history': [
        for (final e in application.history) e.toMap(),
        ApplicationEvent(status: target, note: cleanNote, createdAt: now).toMap(),
      ],
    });
    final emailId = _emails.enqueue(application, target, cleanNote);
    await write;
    final queued = await emailId;
    _changes.bump();
    await _emails.flush();
    return _emails.statusOf(queued);
  }

  List<ApplicationModel> _list(bool Function(Map<String, dynamic>) test) => [
        for (final d in _store.where(_applications, test)) ApplicationModel.fromMap(d.id, d.data),
      ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  Future<ApplicationModel?> byId(String id) async {
    final data = _store.get(_applications, id);
    return data == null ? null : ApplicationModel.fromMap(id, data);
  }

  Future<List<ApplicationModel>> byStudent(String studentId) async => _list((d) => d['candidateId'] == studentId);

  Future<List<ApplicationModel>> byRecruiter(String recruiterId) async {
    final jobIds = _store.where(_jobs, (d) => d['recruiterId'] == recruiterId).map((d) => d.id).toSet();
    return _list((d) => jobIds.contains(d['jobOfferId']));
  }

  Future<List<ApplicationModel>> byJob(String jobId) async =>
      _list((d) => d['jobOfferId'] == jobId)..sort((a, b) => b.appliedAt.compareTo(a.appliedAt));

  Future<List<ApplicationModel>> all() async => _list((_) => true);

  Future<Set<String>> appliedJobIds(String studentId) async =>
      _store.where(_applications, (d) => d['candidateId'] == studentId).map((d) => d.data['jobOfferId'] as String).toSet();

  Future<List<ApplicationEvent>> events(String applicationId) async => (await byId(applicationId))?.history ?? const [];
}
