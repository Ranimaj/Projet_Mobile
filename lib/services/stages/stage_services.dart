import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:mailer/smtp_server.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/app_constants.dart';
import '../../models/user_model.dart';
import '../local_store.dart';
import 'admin_stats.dart';
import 'application_repository.dart';
import 'cv_storage.dart';
import 'db_changes.dart';
import 'email_service.dart';
import 'experience_repository.dart';
import 'job_repository.dart';
import 'matching_service.dart';

/// Les dépôts du module Stage & Emploi, sur la base partagée de l'application.
class StageServices {
  StageServices({
    LocalStore? store,
    AppConfig config = const AppConfig(),
    CvStorage? cvStorage,
    SmtpServer? smtpServer,
    String? emailFrom,
    http.Client? httpClient,
  })  : store = store ?? LocalStore(),
        changes = DbChanges(),
        cvs = cvStorage ?? CvStorage() {
    jobs = JobRepository(this.store, changes, cvs);
    emails = EmailService(this.store, changes, config, server: smtpServer, from: emailFrom);
    applications = ApplicationRepository(this.store, changes, cvs, emails);
    experiences = ExperienceRepository(this.store, changes);
    matching = MatchingService(this.store, changes, experiences, config, client: httpClient);
    // Un profil modifié ailleurs dans l'app change les scores affichés.
    _users = this.store.watch(AppConstants.usersCollection).skip(1).listen((_) => changes.bump());
  }

  final LocalStore store;
  final DbChanges changes;
  final CvStorage cvs;
  late final JobRepository jobs;
  late final EmailService emails;
  late final ApplicationRepository applications;
  late final ExperienceRepository experiences;
  late final MatchingService matching;
  late final StreamSubscription<void> _users;

  AppUser? userById(String id) {
    final data = store.get(AppConstants.usersCollection, id);
    return data == null ? null : AppUser.fromMap(id, data);
  }

  Future<AdminStats> adminStats() async => AdminStats.load(store);

  /// Efface les données du module liées à un compte supprimé.
  Future<void> deleteUserData(String uid) async {
    for (final job in await jobs.byRecruiter(uid)) {
      await jobs.delete(job.id);
    }
    for (final a in await applications.byStudent(uid)) {
      final path = a.cvUrl;
      if (path != null) await cvs.delete(path);
      await store.delete(AppConstants.applicationsCollection, a.id);
    }
    await store.deleteWhere(AppConstants.stageExperiencesCollection, (d) => d['userId'] == uid);
    await store.deleteWhere(AppConstants.stageMatchScoresCollection, (d) => d['studentId'] == uid);
    changes.bump();
  }

  void dispose() {
    _users.cancel();
    changes.dispose();
  }
}
