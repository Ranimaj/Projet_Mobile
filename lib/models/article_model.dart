import 'package:cloud_firestore/cloud_firestore.dart';

enum ArticleStatus { available, reserved, done }

/// Modèle "Gestion Vente & Don".
class ArticleModel {
  final String id;
  final String ownerId;
  final String ownerName;
  final String title;
  final String description;
  final double? price; // null = don gratuit
  final String category;
  final List<String> imageUrls;
  final ArticleStatus status;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;
  final int viewCount;
  final List<String> favoritedBy;

  /// true si l'élément existe seulement en local et attend une synchro réseau.
  final bool pendingSync;

  const ArticleModel({
    required this.id,
    required this.ownerId,
    required this.ownerName,
    required this.title,
    required this.description,
    this.price,
    required this.category,
    this.imageUrls = const [],
    this.status = ArticleStatus.available,
    this.latitude,
    this.longitude,
    required this.createdAt,
    this.viewCount = 0,
    this.favoritedBy = const [],
    this.pendingSync = false,
  });

  bool get isFree => price == null || price == 0;

  factory ArticleModel.fromMap(String id, Map<String, dynamic> map) {
    return ArticleModel(
      id: id,
      ownerId: map['ownerId'] ?? '',
      ownerName: map['ownerName'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      price: map['price'] == null ? null : (map['price'] as num).toDouble(),
      category: map['category'] ?? 'Autre',
      imageUrls: List<String>.from(map['imageUrls'] ?? []),
      status: ArticleStatus.values.firstWhere(
        (s) => s.name == (map['status'] ?? 'available'),
        orElse: () => ArticleStatus.available,
      ),
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      createdAt: (map['createdAt'] is Timestamp)
          ? (map['createdAt'] as Timestamp).toDate()
          : DateTime.tryParse(map['createdAt']?.toString() ?? '') ?? DateTime.now(),
      viewCount: map['viewCount'] ?? 0,
      favoritedBy: List<String>.from(map['favoritedBy'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ownerId': ownerId,
      'ownerName': ownerName,
      'title': title,
      'description': description,
      'price': price,
      'category': category,
      'imageUrls': imageUrls,
      'status': status.name,
      'latitude': latitude,
      'longitude': longitude,
      'createdAt': Timestamp.fromDate(createdAt),
      'viewCount': viewCount,
      'favoritedBy': favoritedBy,
    };
  }

  ArticleModel copyWith({
    String? title,
    String? description,
    double? price,
    String? category,
    List<String>? imageUrls,
    ArticleStatus? status,
    bool? pendingSync,
  }) {
    return ArticleModel(
      id: id,
      ownerId: ownerId,
      ownerName: ownerName,
      title: title ?? this.title,
      description: description ?? this.description,
      price: price ?? this.price,
      category: category ?? this.category,
      imageUrls: imageUrls ?? this.imageUrls,
      status: status ?? this.status,
      latitude: latitude,
      longitude: longitude,
      createdAt: createdAt,
      viewCount: viewCount,
      favoritedBy: favoritedBy,
      pendingSync: pendingSync ?? this.pendingSync,
    );
  }
}
