import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

import '../core/constants/app_constants.dart';

enum UserRole { student, admin, recruiter }

/// Statut de vérification de la carte étudiante.
enum StudentCardStatus { none, pending, verified, rejected }

/// Carte étudiante soumise pour vérification. Seul un admin peut la faire
/// passer à `verified` / `rejected` — voir `firestore.rules`.
class StudentCard extends Equatable {
  final StudentCardStatus status;
  final String? imagePath; // chemin Storage
  final DateTime? submittedAt;
  final String? reviewedBy; // uid admin
  final DateTime? reviewedAt;
  final String? rejectReason;

  const StudentCard({
    this.status = StudentCardStatus.none,
    this.imagePath,
    this.submittedAt,
    this.reviewedBy,
    this.reviewedAt,
    this.rejectReason,
  });

  static const none = StudentCard();

  factory StudentCard.fromMap(Map<String, dynamic>? map) {
    if (map == null) return none;
    return StudentCard(
      status: StudentCardStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => StudentCardStatus.none,
      ),
      imagePath: map['imagePath'],
      submittedAt: AppUser._parseDate(map['submittedAt']),
      reviewedBy: map['reviewedBy'],
      reviewedAt: AppUser._parseDate(map['reviewedAt']),
      rejectReason: map['rejectReason'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'status': status.name,
      'imagePath': imagePath,
      'submittedAt': submittedAt == null ? null : Timestamp.fromDate(submittedAt!),
      'reviewedBy': reviewedBy,
      'reviewedAt': reviewedAt == null ? null : Timestamp.fromDate(reviewedAt!),
      'rejectReason': rejectReason,
    };
  }

  StudentCard copyWith({
    StudentCardStatus? status,
    String? imagePath,
    DateTime? submittedAt,
    String? reviewedBy,
    DateTime? reviewedAt,
    String? rejectReason,
  }) {
    return StudentCard(
      status: status ?? this.status,
      imagePath: imagePath ?? this.imagePath,
      submittedAt: submittedAt ?? this.submittedAt,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      rejectReason: rejectReason ?? this.rejectReason,
    );
  }

  @override
  List<Object?> get props =>
      [status, imagePath, submittedAt, reviewedBy, reviewedAt, rejectReason];
}

/// Modèle "Gestion des Utilisateurs" — profil, vérification, rôle.
class AppUser {
  final String id;
  final String fullName;
  final String email;
  final String? photoUrl;
  final String? major; // filière
  final String? year; // année d'étude
  final bool isVerifiedStudent;
  final bool isPhoneVerified;
  final String? phoneNumber; // format E.164, renseigné après vérification OTP
  final UserRole role;
  final bool twoFactorEnabled;
  final DateTime createdAt;
  final double ratingAverage;
  final int ratingCount;
  final List<String> skills;
  final DateTime? updatedAt;
  final String campus;
  final String? studentId; // identifiant saisi par l'étudiant
  final bool disabled; // compte désactivé, admin uniquement
  final StudentCard studentCard;

  /// Champs qu'un utilisateur peut modifier lui-même. Tout le reste (rôle,
  /// statut de vérification, notes, email, téléphone) est géré côté serveur
  /// ou par un admin — voir `firestore.rules`.
  static const Set<String> editableFields = {
    'fullName',
    'major',
    'year',
    'photoUrl',
    'skills',
    'twoFactorEnabled',
    'campus',
    'studentId',
    'studentCard',
  };

  const AppUser({
    required this.id,
    required this.fullName,
    required this.email,
    this.photoUrl,
    this.major,
    this.year,
    this.isVerifiedStudent = false,
    this.isPhoneVerified = false,
    this.phoneNumber,
    this.role = UserRole.student,
    this.twoFactorEnabled = false,
    required this.createdAt,
    this.ratingAverage = 0,
    this.ratingCount = 0,
    this.skills = const [],
    this.updatedAt,
    this.campus = AppConstants.defaultCampus,
    this.studentId,
    this.disabled = false,
    this.studentCard = StudentCard.none,
  });

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  factory AppUser.fromMap(String id, Map<String, dynamic> map) {
    return AppUser(
      id: id,
      fullName: map['fullName'] ?? '',
      email: map['email'] ?? '',
      photoUrl: map['photoUrl'],
      major: map['major'],
      year: map['year'],
      isVerifiedStudent: map['isVerifiedStudent'] ?? false,
      isPhoneVerified: map['isPhoneVerified'] ?? false,
      phoneNumber: map['phoneNumber'],
      role: UserRole.values.firstWhere(
        (r) => r.name == (map['role'] ?? 'student'),
        orElse: () => UserRole.student,
      ),
      twoFactorEnabled: map['twoFactorEnabled'] ?? false,
      createdAt: _parseDate(map['createdAt']) ?? DateTime.now(),
      ratingAverage: (map['ratingAverage'] ?? 0).toDouble(),
      ratingCount: map['ratingCount'] ?? 0,
      skills: List<String>.from(map['skills'] ?? []),
      updatedAt: _parseDate(map['updatedAt']),
      campus: map['campus'] ?? AppConstants.defaultCampus,
      studentId: map['studentId'],
      disabled: map['disabled'] ?? false,
      studentCard: StudentCard.fromMap(map['studentCard'] is Map
          ? Map<String, dynamic>.from(map['studentCard'] as Map)
          : null),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '');
  }

  Map<String, dynamic> toMap() {
    return {
      'fullName': fullName,
      'email': email,
      'photoUrl': photoUrl,
      'major': major,
      'year': year,
      'isVerifiedStudent': isVerifiedStudent,
      'isPhoneVerified': isPhoneVerified,
      'phoneNumber': phoneNumber,
      'role': role.name,
      'twoFactorEnabled': twoFactorEnabled,
      'createdAt': Timestamp.fromDate(createdAt),
      'ratingAverage': ratingAverage,
      'ratingCount': ratingCount,
      'skills': skills,
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      'campus': campus,
      'studentId': studentId,
      'disabled': disabled,
      'studentCard': studentCard.toMap(),
    };
  }

  /// Sous-ensemble de [toMap] limité aux [editableFields] — c'est tout ce
  /// qu'une mise à jour de profil côté client est autorisée à écrire.
  Map<String, dynamic> toEditableMap() {
    return {
      for (final entry in toMap().entries)
        if (editableFields.contains(entry.key)) entry.key: entry.value,
    };
  }

  AppUser copyWith({
    String? fullName,
    String? photoUrl,
    String? major,
    String? year,
    bool? isVerifiedStudent,
    bool? isPhoneVerified,
    String? phoneNumber,
    bool? twoFactorEnabled,
    List<String>? skills,
    DateTime? updatedAt,
    String? campus,
    String? studentId,
    StudentCard? studentCard,
  }) {
    return AppUser(
      id: id,
      fullName: fullName ?? this.fullName,
      email: email,
      photoUrl: photoUrl ?? this.photoUrl,
      major: major ?? this.major,
      year: year ?? this.year,
      isVerifiedStudent: isVerifiedStudent ?? this.isVerifiedStudent,
      isPhoneVerified: isPhoneVerified ?? this.isPhoneVerified,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      role: role,
      twoFactorEnabled: twoFactorEnabled ?? this.twoFactorEnabled,
      createdAt: createdAt,
      ratingAverage: ratingAverage,
      ratingCount: ratingCount,
      skills: skills ?? this.skills,
      updatedAt: updatedAt ?? this.updatedAt,
      campus: campus ?? this.campus,
      studentId: studentId ?? this.studentId,
      disabled: disabled,
      studentCard: studentCard ?? this.studentCard,
    );
  }
}
