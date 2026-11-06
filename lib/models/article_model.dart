import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/geo.dart';
import '../services/local_photo_store.dart';

enum ArticleStatus { available, reserved, done }

/// Modèle "Gestion Vente & Don".
class ArticleModel {
  /// Nombre maximal de photos par article.
  static const int maxPhotos = 6;

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
  final DateTime? updatedAt;
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
    this.updatedAt,
    this.viewCount = 0,
    this.favoritedBy = const [],
    this.pendingSync = false,
  });

  bool get isFree => price == null || price == 0;

  bool get isAvailable => status == ArticleStatus.available;

  bool get hasLocation => latitude != null && longitude != null;

  GeoPoint2? get location => hasLocation ? GeoPoint2(latitude!, longitude!) : null;

  /// Des photos sont encore sur le téléphone (publiées sans réseau).
  bool get hasLocalPhotos => imageUrls.any(isLocalImage);

  /// Première photo, ou null s'il n'y en a pas.
  String? get coverUrl => imageUrls.isEmpty ? null : imageUrls.first;

  /// « Gratuit » ou « 25 DT » (« 12,5 DT » pour un prix non entier).
  String get priceLabel {
    if (isFree) return 'Gratuit';
    final p = price!;
    final text = p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(1).replaceAll('.', ',');
    return '$text DT';
  }

  bool isFavoriteOf(String? userId) => userId != null && favoritedBy.contains(userId);

  /// Distance en km depuis [from], ou null si l'un des deux points manque.
  double? distanceKmFrom(GeoPoint2? from) {
    final here = location;
    if (from == null || here == null) return null;
    return distanceKm(from, here);
  }

  static DateTime? _date(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

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
      createdAt: _date(map['createdAt']) ?? DateTime.now(),
      updatedAt: _date(map['updatedAt']),
      viewCount: (map['viewCount'] as num?)?.toInt() ?? 0,
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
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
      'viewCount': viewCount,
      'favoritedBy': favoritedBy,
    };
  }

  /// [clearPrice] passe l'article en don ; [clearLocation] retire la position.
  ArticleModel copyWith({
    String? title,
    String? description,
    double? price,
    bool clearPrice = false,
    String? category,
    List<String>? imageUrls,
    ArticleStatus? status,
    double? latitude,
    double? longitude,
    bool clearLocation = false,
    DateTime? updatedAt,
    int? viewCount,
    List<String>? favoritedBy,
    bool? pendingSync,
  }) {
    return ArticleModel(
      id: id,
      ownerId: ownerId,
      ownerName: ownerName,
      title: title ?? this.title,
      description: description ?? this.description,
      price: clearPrice ? null : (price ?? this.price),
      category: category ?? this.category,
      imageUrls: imageUrls ?? this.imageUrls,
      status: status ?? this.status,
      latitude: clearLocation ? null : (latitude ?? this.latitude),
      longitude: clearLocation ? null : (longitude ?? this.longitude),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      viewCount: viewCount ?? this.viewCount,
      favoritedBy: favoritedBy ?? this.favoritedBy,
      pendingSync: pendingSync ?? this.pendingSync,
    );
  }
}
