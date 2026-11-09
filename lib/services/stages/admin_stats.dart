import '../../core/constants/app_constants.dart';
import '../../models/job_offer_model.dart';
import '../../models/stage_records.dart';
import '../local_store.dart';

/// Chiffres du module Stage & Emploi pour l'administration.
class AdminStats {
  const AdminStats({
    required this.openJobs,
    required this.totalJobs,
    required this.applicationsByStatus,
    required this.emailsSent,
    required this.emailsWaiting,
    required this.emailsFailed,
  });

  final int openJobs;
  final int totalJobs;
  final Map<ApplicationStatus, int> applicationsByStatus;
  final int emailsSent;
  final int emailsWaiting;
  final int emailsFailed;

  int get totalApplications => applicationsByStatus.values.fold(0, (a, b) => a + b);

  factory AdminStats.load(LocalStore store) {
    final jobs = [for (final d in store.all(AppConstants.jobOffersCollection)) JobOfferModel.fromMap(d.id, d.data)];
    final byStatus = {for (final s in ApplicationStatus.values) s: 0};
    for (final d in store.all(AppConstants.applicationsCollection)) {
      final status = ApplicationStatus.parse(d.data['status']);
      byStatus[status] = byStatus[status]! + 1;
    }
    int emails(EmailStatus status) =>
        store.where(AppConstants.stageEmailsCollection, (d) => d['status'] == status.name).length;
    return AdminStats(
      openJobs: jobs.where((j) => j.acceptsApplications).length,
      totalJobs: jobs.length,
      applicationsByStatus: byStatus,
      emailsSent: emails(EmailStatus.sent),
      emailsWaiting: emails(EmailStatus.pending),
      emailsFailed: emails(EmailStatus.failed),
    );
  }
}
