import '../core/utils/segment_topics.dart';

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
  final DateTime? updatedAt;
  final int commentCount;

  /// Segmentation des notifications : listes vides = tout le campus.
  final List<String> targetMajors; // filières (libellés officiels)
  final List<String> targetYears; // années (libellés officiels)

  /// Demande l'envoi d'une notification push à la création (Cloud Function).
  final bool sendPush;

  /// Lieu (ex. objet trouvé), issu de la recherche OpenStreetMap.
  final String? locationName;
  final double? latitude;
  final double? longitude;

  /// Local uniquement (non stocké) : action encore dans la file hors-ligne.
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
    this.updatedAt,
    this.commentCount = 0,
    this.targetMajors = const [],
    this.targetYears = const [],
    this.sendPush = false,
    this.locationName,
    this.latitude,
    this.longitude,
    this.pendingSync = false,
  });

  bool get hasLocation => latitude != null && longitude != null;
  bool get isOfficial => category == 'Officielle';
  bool get isTargeted => targetMajors.isNotEmpty || targetYears.isNotEmpty;

  /// Libellé lisible du ciblage, ex. "Informatique · 3ème année".
  String get targetLabel {
    if (!isTargeted) return 'Tout le campus';
    final parts = <String>[
      if (targetMajors.isNotEmpty) targetMajors.join(', '),
      if (targetYears.isNotEmpty) targetYears.join(', '),
    ];
    return parts.join(' · ');
  }

  /// Vrai si l'annonce concerne un étudiant (filière ET année), les listes
  /// vides signifiant "pas de restriction".
  bool matchesUser({String? major, String? year}) {
    final majorOk = targetMajors.isEmpty ||
        (SegmentTopics.majorTopic(major) != null &&
            SegmentTopics.majorTopics(targetMajors).contains(SegmentTopics.majorTopic(major)));
    final yearOk = targetYears.isEmpty ||
        (SegmentTopics.yearTopic(year) != null &&
            SegmentTopics.yearTopics(targetYears).contains(SegmentTopics.yearTopic(year)));
    return majorOk && yearOk;
  }

  /// Texte utilisé par la recherche (titre + contenu + auteur + catégorie).
  bool matchesQuery(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return title.toLowerCase().contains(q) ||
        content.toLowerCase().contains(q) ||
        authorName.toLowerCase().contains(q) ||
        category.toLowerCase().contains(q);
  }

  AnnonceModel copyWith({
    String? title,
    String? content,
    String? category,
    bool? isPinned,
    bool? isUrgent,
    DateTime? updatedAt,
    List<String>? targetMajors,
    List<String>? targetYears,
    bool? sendPush,
    bool? pendingSync,
    String? locationName,
    double? latitude,
    double? longitude,
  }) {
    return AnnonceModel(
      id: id,
      authorId: authorId,
      authorName: authorName,
      title: title ?? this.title,
      content: content ?? this.content,
      category: category ?? this.category,
      isPinned: isPinned ?? this.isPinned,
      isUrgent: isUrgent ?? this.isUrgent,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      commentCount: commentCount,
      targetMajors: targetMajors ?? this.targetMajors,
      targetYears: targetYears ?? this.targetYears,
      sendPush: sendPush ?? this.sendPush,
      pendingSync: pendingSync ?? this.pendingSync,
      locationName: locationName ?? this.locationName,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
    );
  }

  /// Copie après modification par l'auteur / l'admin. Contrairement à
  /// [copyWith], le lieu peut être effacé (valeurs nulles) ; [isPinned] n'est
  /// changé que s'il est fourni.
  AnnonceModel edited({
    required String title,
    required String content,
    required String category,
    required bool isUrgent,
    required List<String> targetMajors,
    required List<String> targetYears,
    String? locationName,
    double? latitude,
    double? longitude,
    required DateTime updatedAt,
    bool? isPinned,
  }) {
    return AnnonceModel(
      id: id,
      authorId: authorId,
      authorName: authorName,
      title: title,
      content: content,
      category: category,
      isPinned: isPinned ?? this.isPinned,
      isUrgent: isUrgent,
      createdAt: createdAt,
      updatedAt: updatedAt,
      commentCount: commentCount,
      targetMajors: targetMajors,
      targetYears: targetYears,
      sendPush: sendPush,
      locationName: locationName,
      latitude: latitude,
      longitude: longitude,
      pendingSync: pendingSync,
    );
  }
}
