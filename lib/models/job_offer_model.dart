import '../services/local_store.dart' show parseDate;

enum JobType {
  stage('Stage'),
  emploi('Emploi');

  const JobType(this.label);
  final String label;
}

/// Modèle "Gestion Stage & Emploi".
class JobOfferModel {
  final String id;
  final String recruiterId;
  final String companyName;
  final String title;
  final String description;
  final JobType type;
  final String location;
  final String duration;
  final String requirements;
  final List<String> requiredSkills;
  final DateTime postedAt;
  final DateTime? deadline;
  final bool isOpen;
  final bool pendingSync;

  /// Calculé à la lecture, jamais stocké.
  final int applicantCount;

  const JobOfferModel({
    required this.id,
    required this.recruiterId,
    required this.companyName,
    required this.title,
    required this.description,
    required this.type,
    required this.location,
    this.duration = '',
    this.requirements = '',
    this.requiredSkills = const [],
    required this.postedAt,
    this.deadline,
    this.isOpen = true,
    this.pendingSync = false,
    this.applicantCount = 0,
  });

  /// La date limite reste valable toute la journée indiquée.
  bool get isExpired {
    final d = deadline;
    if (d == null) return false;
    return DateTime.now().isAfter(DateTime(d.year, d.month, d.day, 23, 59, 59));
  }

  bool get acceptsApplications => isOpen && !isExpired;

  /// Score de correspondance avec les compétences d'un candidat (0 à 1).
  double matchScore(List<String> candidateSkills) {
    if (requiredSkills.isEmpty) return 0;
    final matched = requiredSkills.where((s) =>
        candidateSkills.any((c) => c.toLowerCase() == s.toLowerCase())).length;
    return matched / requiredSkills.length;
  }

  factory JobOfferModel.fromMap(String id, Map<String, dynamic> map, {int applicantCount = 0}) {
    return JobOfferModel(
      id: id,
      recruiterId: map['recruiterId'] ?? '',
      companyName: map['companyName'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      type: JobType.values.firstWhere(
        (t) => t.name == (map['type'] ?? 'stage'),
        orElse: () => JobType.stage,
      ),
      location: map['location'] ?? '',
      duration: map['duration'] ?? '',
      requirements: map['requirements'] ?? '',
      requiredSkills: List<String>.from(map['requiredSkills'] ?? []),
      postedAt: parseDate(map['postedAt']) ?? DateTime.now(),
      deadline: parseDate(map['deadline']),
      isOpen: map['isOpen'] ?? true,
      applicantCount: applicantCount,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'recruiterId': recruiterId,
      'companyName': companyName,
      'title': title,
      'description': description,
      'type': type.name,
      'location': location,
      'duration': duration,
      'requirements': requirements,
      'requiredSkills': requiredSkills,
      'postedAt': postedAt,
      'deadline': deadline,
      'isOpen': isOpen,
    };
  }
}

/// Étapes du suivi d'une candidature. Chaque changement envoie un email.
enum ApplicationStatus {
  pending('En attente'),
  hrInterview('Entretien RH'),
  technicalInterview('Entretien technique'),
  accepted('Acceptée'),
  rejected('Refusée');

  const ApplicationStatus(this.label);
  final String label;

  bool get isFinal => this == accepted || this == rejected;

  /// Étape suivante du parcours ; le refus reste possible à toute étape ouverte.
  ApplicationStatus? get next => switch (this) {
        pending => hrInterview,
        hrInterview => technicalInterview,
        technicalInterview => accepted,
        accepted || rejected => null,
      };

  bool canMoveTo(ApplicationStatus target) => !isFinal && (target == next || target == rejected);

  /// Libellé du bouton qui fait passer à cette étape.
  String get actionLabel => switch (this) {
        pending => 'Remettre en attente',
        hrInterview => 'Accepter pour l\'entretien RH',
        technicalInterview => 'Passer à l\'entretien technique',
        accepted => 'Accepter la candidature',
        rejected => 'Refuser',
      };

  /// Étapes affichées dans la frise (hors refus).
  static const pipeline = [pending, hrInterview, technicalInterview, accepted];

  static ApplicationStatus parse(Object? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => pending);
}

/// Une étape franchie, conservée dans le document de la candidature.
class ApplicationEvent {
  const ApplicationEvent({required this.status, this.note = '', required this.createdAt});

  final ApplicationStatus status;
  final String note;
  final DateTime createdAt;

  factory ApplicationEvent.fromMap(Map<String, dynamic> map) => ApplicationEvent(
        status: ApplicationStatus.parse(map['status']),
        note: map['note'] ?? '',
        createdAt: parseDate(map['createdAt']) ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {'status': status.name, 'note': note, 'createdAt': createdAt};
}

/// Modèle de suivi de candidature — relie un étudiant à une offre.
class ApplicationModel {
  final String id;
  final String jobOfferId;
  final String jobTitle;
  final String companyName;
  final String candidateId;
  final String studentName;
  final String studentEmail;
  final String? cvUrl;
  final String cvName;
  final String? coverLetter;
  final String message;
  final ApplicationStatus status;
  final DateTime appliedAt;
  final DateTime updatedAt;
  final List<ApplicationEvent> history;
  final bool pendingSync;

  ApplicationModel({
    required this.id,
    required this.jobOfferId,
    required this.jobTitle,
    required this.companyName,
    required this.candidateId,
    this.studentName = '',
    this.studentEmail = '',
    this.cvUrl,
    this.cvName = '',
    this.coverLetter,
    this.message = '',
    this.status = ApplicationStatus.pending,
    required this.appliedAt,
    DateTime? updatedAt,
    this.history = const [],
    this.pendingSync = false,
  }) : updatedAt = updatedAt ?? appliedAt;

  factory ApplicationModel.fromMap(String id, Map<String, dynamic> map) {
    final appliedAt = parseDate(map['appliedAt']) ?? DateTime.now();
    return ApplicationModel(
      id: id,
      jobOfferId: map['jobOfferId'] ?? '',
      jobTitle: map['jobTitle'] ?? '',
      companyName: map['companyName'] ?? '',
      candidateId: map['candidateId'] ?? '',
      studentName: map['studentName'] ?? '',
      studentEmail: map['studentEmail'] ?? '',
      cvUrl: map['cvUrl'],
      cvName: map['cvName'] ?? '',
      coverLetter: map['coverLetter'],
      message: map['message'] ?? '',
      status: ApplicationStatus.parse(map['status']),
      appliedAt: appliedAt,
      updatedAt: parseDate(map['updatedAt']) ?? appliedAt,
      history: [
        for (final e in (map['history'] as List? ?? const []))
          ApplicationEvent.fromMap(Map<String, dynamic>.from(e as Map)),
      ],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'jobOfferId': jobOfferId,
      'jobTitle': jobTitle,
      'companyName': companyName,
      'candidateId': candidateId,
      'studentName': studentName,
      'studentEmail': studentEmail,
      'cvUrl': cvUrl,
      'cvName': cvName,
      'coverLetter': coverLetter,
      'message': message,
      'status': status.name,
      'appliedAt': appliedAt,
      'updatedAt': updatedAt,
      'history': [for (final e in history) e.toMap()],
    };
  }
}
