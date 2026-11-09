import '../services/local_store.dart' show parseDate;

enum EmailStatus { pending, sent, failed, skipped }

/// Email de la file d'envoi du module Stage & Emploi.
class EmailRecord {
  const EmailRecord({
    required this.id,
    required this.recipient,
    required this.subject,
    required this.body,
    required this.status,
    required this.attempts,
    required this.error,
    required this.createdAt,
  });

  final String id;
  final String recipient;
  final String subject;
  final String body;
  final EmailStatus status;
  final int attempts;
  final String error;
  final DateTime createdAt;

  factory EmailRecord.fromMap(String id, Map<String, dynamic> map) => EmailRecord(
        id: id,
        recipient: map['recipient'] ?? '',
        subject: map['subject'] ?? '',
        body: map['body'] ?? '',
        status: EmailStatus.values.byName(map['status'] ?? 'pending'),
        attempts: map['attempts'] ?? 0,
        error: map['error'] ?? '',
        createdAt: parseDate(map['createdAt']) ?? DateTime.now(),
      );
}

/// Score de compatibilité étudiant ↔ offre.
class MatchScore {
  const MatchScore({required this.score, required this.reason, required this.isAi});

  final int score;
  final String reason;

  /// `true` : calculé par Gemini ; `false` : estimation locale sur les compétences.
  final bool isAi;
}

enum ExperienceKind {
  education('Formation'),
  work('Expérience');

  const ExperienceKind(this.label);
  final String label;
}

/// Ligne du cursus d'un étudiant, utilisée par le matching.
class Experience {
  const Experience({
    required this.id,
    required this.userId,
    required this.kind,
    required this.title,
    required this.organization,
    this.period = '',
    this.description = '',
  });

  final String id;
  final String userId;
  final ExperienceKind kind;
  final String title;
  final String organization;
  final String period;
  final String description;

  factory Experience.fromMap(String id, Map<String, dynamic> map) => Experience(
        id: id,
        userId: map['userId'] ?? '',
        kind: ExperienceKind.values.byName(map['kind'] ?? 'education'),
        title: map['title'] ?? '',
        organization: map['organization'] ?? '',
        period: map['period'] ?? '',
        description: map['description'] ?? '',
      );
}
