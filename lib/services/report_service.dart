import 'package:cloud_firestore/cloud_firestore.dart';

/// Motif d'un signalement.
enum ReportReason {
  scam('Arnaque ou tentative d\'arnaque'),
  notAsDescribed('Objet non conforme à l\'annonce'),
  behavior('Comportement inapproprié'),
  fakeProfile('Faux profil'),
  other('Autre');

  const ReportReason(this.label);
  final String label;
}

enum ReportStatus { pending, confirmed, dismissed }

/// Signalement d'un utilisateur (`reports/{reporterId}_{targetId}`) : un
/// seul par personne et par compte signalé.
class UserReport {
  final String id;
  final String reporterId;
  final String reporterName;
  final String targetId;
  final String targetName;
  final ReportReason reason;
  final String details;
  final String? articleId;
  final DateTime? createdAt;
  final ReportStatus status;

  const UserReport({
    required this.id,
    required this.reporterId,
    required this.reporterName,
    required this.targetId,
    required this.targetName,
    required this.reason,
    this.details = '',
    this.articleId,
    this.createdAt,
    this.status = ReportStatus.pending,
  });

  factory UserReport.fromMap(String id, Map<String, dynamic> m) => UserReport(
        id: id,
        reporterId: m['reporterId'] as String? ?? '',
        reporterName: m['reporterName'] as String? ?? '',
        targetId: m['targetId'] as String? ?? '',
        targetName: m['targetName'] as String? ?? '',
        reason: ReportReason.values.firstWhere((r) => r.name == m['reason'], orElse: () => ReportReason.other),
        details: m['details'] as String? ?? '',
        articleId: m['articleId'] as String?,
        createdAt: m['createdAt'] is Timestamp ? (m['createdAt'] as Timestamp).toDate() : null,
        status: ReportStatus.values.firstWhere((s) => s.name == m['status'], orElse: () => ReportStatus.pending),
      );
}

/// Le compte a déjà été signalé par cet utilisateur.
class AlreadyReported implements Exception {
  const AlreadyReported();
}

/// Signalements : envoi par les utilisateurs, traitement par les admins.
/// Un signalement confirmé ajoute 1 à `reportCount` du compte visé, ce qui
/// fait baisser son score de confiance.
class ReportService {
  ReportService(this._db);
  final FirebaseFirestore _db;

  static const maxDetails = 500;

  CollectionReference<Map<String, dynamic>> get _reports => _db.collection('reports');

  static String idFor(String reporterId, String targetId) => '${reporterId}_$targetId';

  Future<void> submit({
    required String reporterId,
    required String reporterName,
    required String targetId,
    required String targetName,
    required ReportReason reason,
    String details = '',
    String? articleId,
  }) async {
    if (reporterId == targetId) throw ArgumentError('On ne peut pas se signaler soi-même.');
    final ref = _reports.doc(idFor(reporterId, targetId));
    if ((await ref.get()).exists) throw const AlreadyReported();
    final text = details.trim();
    await ref.set({
      'reporterId': reporterId,
      'reporterName': reporterName,
      'targetId': targetId,
      'targetName': targetName,
      'reason': reason.name,
      'details': text.length > maxDetails ? text.substring(0, maxDetails) : text,
      if (articleId != null) 'articleId': articleId,
      'createdAt': FieldValue.serverTimestamp(),
      'status': ReportStatus.pending.name,
    });
  }

  /// Signalements à traiter, les plus anciens d'abord.
  Stream<List<UserReport>> watchPending() => _reports
      .where('status', isEqualTo: ReportStatus.pending.name)
      .snapshots()
      .map((s) => [for (final d in s.docs) UserReport.fromMap(d.id, d.data())]
        ..sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0))));

  /// Le signalement est fondé : le compte perd des points de confiance.
  Future<void> confirm(UserReport report, {required String adminId}) async {
    final batch = _db.batch()
      ..update(_reports.doc(report.id), {
        'status': ReportStatus.confirmed.name,
        'reviewedBy': adminId,
        'reviewedAt': FieldValue.serverTimestamp(),
      })
      ..update(_db.collection('users').doc(report.targetId), {'reportCount': FieldValue.increment(1)});
    await batch.commit();
  }

  Future<void> dismiss(UserReport report, {required String adminId}) => _reports.doc(report.id).update({
        'status': ReportStatus.dismissed.name,
        'reviewedBy': adminId,
        'reviewedAt': FieldValue.serverTimestamp(),
      });
}
