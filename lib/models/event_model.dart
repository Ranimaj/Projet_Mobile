import 'package:cloud_firestore/cloud_firestore.dart';

/// Modèle "Gestion des Événements".
class EventModel {
  final String id;
  final String organizerId;
  final String organizerName;
  final String title;
  final String description;
  final String category;
  final DateTime startDate;
  final String location;
  final double? latitude;
  final double? longitude;
  final List<String> registeredUserIds;
  final String? posterUrl;
  final bool pendingSync;

  const EventModel({
    required this.id,
    required this.organizerId,
    required this.organizerName,
    required this.title,
    required this.description,
    required this.category,
    required this.startDate,
    required this.location,
    this.latitude,
    this.longitude,
    this.registeredUserIds = const [],
    this.posterUrl,
    this.pendingSync = false,
  });

  bool isUserRegistered(String userId) => registeredUserIds.contains(userId);

  factory EventModel.fromMap(String id, Map<String, dynamic> map) {
    return EventModel(
      id: id,
      organizerId: map['organizerId'] ?? '',
      organizerName: map['organizerName'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      category: map['category'] ?? 'Générale',
      startDate: _parseDate(map['startDate']),
      location: map['location'] ?? '',
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      registeredUserIds: List<String>.from(map['registeredUserIds'] ?? []),
      posterUrl: map['posterUrl'],
    );
  }

  /// La date peut arriver sous 4 formes : Timestamp (Firestore), DateTime
  /// (cache Hive), int (millisecondes) ou String (ISO 8601).
  static DateTime _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  Map<String, dynamic> toMap() {
    return {
      'organizerId': organizerId,
      'organizerName': organizerName,
      'title': title,
      'description': description,
      'category': category,
      'startDate': Timestamp.fromDate(startDate),
      'location': location,
      'latitude': latitude,
      'longitude': longitude,
      'registeredUserIds': registeredUserIds,
      'posterUrl': posterUrl,
    };
  }

  EventModel copyWithRegistration(String userId, bool register) {
    final updated = List<String>.from(registeredUserIds);
    if (register) {
      if (!updated.contains(userId)) updated.add(userId);
    } else {
      updated.remove(userId);
    }
    return EventModel(
      id: id,
      organizerId: organizerId,
      organizerName: organizerName,
      title: title,
      description: description,
      category: category,
      startDate: startDate,
      location: location,
      latitude: latitude,
      longitude: longitude,
      registeredUserIds: updated,
      posterUrl: posterUrl,
    );
  }
}
