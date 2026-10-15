import 'package:cloud_firestore/cloud_firestore.dart';

enum UserRole { student, admin, recruiter }

/// Modèle "Gestion des Utilisateurs" — profil, vérification, rôle.
class AppUser {
  final String id;
  final String fullName;
  final String email;
  final String? photoUrl;
  final String? major; // filière
  final String? year; // année d'étude
  final bool isVerifiedStudent;
  final UserRole role;
  final bool twoFactorEnabled;
  final DateTime createdAt;
  final double ratingAverage;
  final int ratingCount;
  final List<String> skills;

  const AppUser({
    required this.id,
    required this.fullName,
    required this.email,
    this.photoUrl,
    this.major,
    this.year,
    this.isVerifiedStudent = false,
    this.role = UserRole.student,
    this.twoFactorEnabled = false,
    required this.createdAt,
    this.ratingAverage = 0,
    this.ratingCount = 0,
    this.skills = const [],
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
      role: UserRole.values.firstWhere(
        (r) => r.name == (map['role'] ?? 'student'),
        orElse: () => UserRole.student,
      ),
      twoFactorEnabled: map['twoFactorEnabled'] ?? false,
      createdAt: (map['createdAt'] is Timestamp)
          ? (map['createdAt'] as Timestamp).toDate()
          : DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.now(),
      ratingAverage: (map['ratingAverage'] ?? 0).toDouble(),
      ratingCount: map['ratingCount'] ?? 0,
      skills: List<String>.from(map['skills'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'fullName': fullName,
      'email': email,
      'photoUrl': photoUrl,
      'major': major,
      'year': year,
      'isVerifiedStudent': isVerifiedStudent,
      'role': role.name,
      'twoFactorEnabled': twoFactorEnabled,
      'createdAt': Timestamp.fromDate(createdAt),
      'ratingAverage': ratingAverage,
      'ratingCount': ratingCount,
      'skills': skills,
    };
  }

  AppUser copyWith({
    String? fullName,
    String? photoUrl,
    String? major,
    String? year,
    bool? isVerifiedStudent,
    bool? twoFactorEnabled,
    List<String>? skills,
  }) {
    return AppUser(
      id: id,
      fullName: fullName ?? this.fullName,
      email: email,
      photoUrl: photoUrl ?? this.photoUrl,
      major: major ?? this.major,
      year: year ?? this.year,
      isVerifiedStudent: isVerifiedStudent ?? this.isVerifiedStudent,
      role: role,
      twoFactorEnabled: twoFactorEnabled ?? this.twoFactorEnabled,
      createdAt: createdAt,
      ratingAverage: ratingAverage,
      ratingCount: ratingCount,
      skills: skills ?? this.skills,
    );
  }
}
