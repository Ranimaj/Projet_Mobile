import '../core/constants/app_constants.dart';
import 'local_store.dart';

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
        createdAt: parseDate(m['createdAt']),
        status: ReportStatus.values.firstWhere((s) => s.name == m['status'], orElse: () => ReportStatus.pending),
      );
}

/// Le compte a déjà été signalé par cet utilisateur.
class AlreadyReported implements Exception {
  const AlreadyReported();
}

/// Signalements : envoi par les utilisateurs, traitement par les admins
/// (collection `reports` de [LocalStore], sur ce téléphone).
/// Un signalement confirmé ajoute 1 à `reportCount` du compte visé, ce qui
/// fait baisser son score de confiance.
class ReportService {
  ReportService({LocalStore? store, DateTime Function()? clock})
      : _store = store ?? LocalStore(),
        _now = clock ?? DateTime.now;

  final LocalStore _store;
  final DateTime Function() _now;

  static const collection = 'reports';
  static const maxDetails = 500;

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
    final id = idFor(reporterId, targetId);
    if (_store.exists(collection, id)) throw const AlreadyReported();
    final text = details.trim();
    await _store.set(collection, id, {
      'reporterId': reporterId,
      'reporterName': reporterName,
      'targetId': targetId,
      'targetName': targetName,
      'reason': reason.name,
      'details': text.length > maxDetails ? text.substring(0, maxDetails) : text,
      if (articleId != null) 'articleId': articleId,
      'createdAt': _now(),
      'status': ReportStatus.pending.name,
    });
  }

  /// Signalements à traiter, les plus anciens d'abord.
  Stream<List<UserReport>> watchPending() => _store.watch(collection).map((docs) => [
        for (final d in docs)
          if (d.data['status'] == ReportStatus.pending.name) UserReport.fromMap(d.id, d.data),
      ]..sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0))));

  /// Le signalement est fondé : le compte perd des points de confiance.
  /// Un signalement déjà confirmé ne compte pas deux fois (lecture puis
  /// écritures sans `await` entre elles).
  Future<void> confirm(UserReport report, {required String adminId}) async {
    final current = _store.get(collection, report.id);
    if (current == null) throw DocumentNotFound(collection, report.id);
    if (current['status'] == ReportStatus.confirmed.name) return;
    final target = _store.get(AppConstants.usersCollection, report.targetId);
    final count = (target?['reportCount'] as num?)?.toInt() ?? 0;
    final writes = [
      _store.update(collection, report.id, {
        'status': ReportStatus.confirmed.name,
        'reviewedBy': adminId,
        'reviewedAt': _now(),
      }),
      if (target != null) _store.update(AppConstants.usersCollection, report.targetId, {'reportCount': count + 1}),
    ];
    await Future.wait(writes);
  }

  Future<void> dismiss(UserReport report, {required String adminId}) => _store.update(collection, report.id, {
        'status': ReportStatus.dismissed.name,
        'reviewedBy': adminId,
        'reviewedAt': _now(),
      });
}
