import 'package:cloud_firestore/cloud_firestore.dart';

/// Modèle "Gestion des Annonces" (campus).
class AnnonceModel {
  final String id;
  final String authorId;
  final String authorName;
  final String title;
  final String content;
  final String category; // Officielle / Perdu & Trouvé / Générale
  final bool isPinned;
  final bool isUrgent;
  final DateTime createdAt;
  final int commentCount;
  final List<String> targetMajors; // segmentation des notifications
  final bool pendingSync;

  const AnnonceModel({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.title,
    required this.content,
    required this.category,
    this.isPinned = false,
    this.isUrgent = false,
    required this.createdAt,
    this.commentCount = 0,
    this.targetMajors = const [],
    this.pendingSync = false,
  });

  factory AnnonceModel.fromMap(String id, Map<String, dynamic> map) {
    return AnnonceModel(
      id: id,
      authorId: map['authorId'] ?? '',
      authorName: map['authorName'] ?? '',
      title: map['title'] ?? '',
      content: map['content'] ?? '',
      category: map['category'] ?? 'Générale',
      isPinned: map['isPinned'] ?? false,
      isUrgent: map['isUrgent'] ?? false,
      createdAt: (map['createdAt'] is Timestamp)
          ? (map['createdAt'] as Timestamp).toDate()
          : DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.now(),
      commentCount: map['commentCount'] ?? 0,
      targetMajors: List<String>.from(map['targetMajors'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'authorId': authorId,
      'authorName': authorName,
      'title': title,
      'content': content,
      'category': category,
      'isPinned': isPinned,
      'isUrgent': isUrgent,
      'createdAt': Timestamp.fromDate(createdAt),
      'commentCount': commentCount,
      'targetMajors': targetMajors,
    };
  }
}
