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
  final bool isPhoneVerified;
  final String? phoneNumber; // format E.164, renseigné après vérification OTP
  final UserRole role;
  final bool twoFactorEnabled;
  final DateTime createdAt;
  final double ratingAverage;
  final int ratingCount;
  final List<String> skills;
  final DateTime? updatedAt;

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
    );
  }
}
