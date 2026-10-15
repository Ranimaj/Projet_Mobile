import 'package:cloud_firestore/cloud_firestore.dart';

enum JobType { stage, emploi }

/// Modèle "Gestion Stage & Emploi".
class JobOfferModel {
  final String id;
  final String recruiterId;
  final String companyName;
  final String title;
  final String description;
  final JobType type;
  final String location;
  final List<String> requiredSkills;
  final DateTime postedAt;
  final DateTime? deadline;
  final bool pendingSync;

  const JobOfferModel({
    required this.id,
    required this.recruiterId,
    required this.companyName,
    required this.title,
    required this.description,
    required this.type,
    required this.location,
    this.requiredSkills = const [],
    required this.postedAt,
    this.deadline,
    this.pendingSync = false,
  });

  /// Score de correspondance avec les compétences d'un candidat (0 à 1).
  double matchScore(List<String> candidateSkills) {
    if (requiredSkills.isEmpty) return 0;
    final matched = requiredSkills.where((s) =>
        candidateSkills.any((c) => c.toLowerCase() == s.toLowerCase())).length;
    return matched / requiredSkills.length;
  }

  factory JobOfferModel.fromMap(String id, Map<String, dynamic> map) {
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
      requiredSkills: List<String>.from(map['requiredSkills'] ?? []),
      postedAt: (map['postedAt'] is Timestamp)
          ? (map['postedAt'] as Timestamp).toDate()
          : DateTime.tryParse(map['postedAt']?.toString() ?? '') ?? DateTime.now(),
      deadline: map['deadline'] == null
          ? null
          : (map['deadline'] is Timestamp)
              ? (map['deadline'] as Timestamp).toDate()
              : DateTime.tryParse(map['deadline'].toString()),
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
      'requiredSkills': requiredSkills,
      'postedAt': Timestamp.fromDate(postedAt),
      'deadline': deadline == null ? null : Timestamp.fromDate(deadline!),
    };
  }
}

enum ApplicationStatus { sent, seen, accepted, rejected }

/// Modèle de suivi de candidature — relie un étudiant à une offre.
class ApplicationModel {
  final String id;
  final String jobOfferId;
  final String jobTitle;
  final String companyName;
  final String candidateId;
  final String? cvUrl;
  final String? coverLetter;
  final ApplicationStatus status;
  final DateTime appliedAt;
  final bool pendingSync;

  const ApplicationModel({
    required this.id,
    required this.jobOfferId,
    required this.jobTitle,
    required this.companyName,
    required this.candidateId,
    this.cvUrl,
    this.coverLetter,
    this.status = ApplicationStatus.sent,
    required this.appliedAt,
    this.pendingSync = false,
  });

  factory ApplicationModel.fromMap(String id, Map<String, dynamic> map) {
    return ApplicationModel(
      id: id,
      jobOfferId: map['jobOfferId'] ?? '',
      jobTitle: map['jobTitle'] ?? '',
      companyName: map['companyName'] ?? '',
      candidateId: map['candidateId'] ?? '',
      cvUrl: map['cvUrl'],
      coverLetter: map['coverLetter'],
      status: ApplicationStatus.values.firstWhere(
        (s) => s.name == (map['status'] ?? 'sent'),
        orElse: () => ApplicationStatus.sent,
      ),
      appliedAt: (map['appliedAt'] is Timestamp)
          ? (map['appliedAt'] as Timestamp).toDate()
          : DateTime.tryParse(map['appliedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'jobOfferId': jobOfferId,
      'jobTitle': jobTitle,
      'companyName': companyName,
      'candidateId': candidateId,
      'cvUrl': cvUrl,
      'coverLetter': coverLetter,
      'status': status.name,
      'appliedAt': Timestamp.fromDate(appliedAt),
    };
  }
}
