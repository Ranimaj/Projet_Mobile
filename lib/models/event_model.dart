import 'package:cloud_firestore/cloud_firestore.dart';

/// Statut STOCKÉ dans Firestore : seule l'annulation est une décision humaine.
enum EventStatus { active, cancelled }

/// Statut AFFICHÉ, toujours calculé (jamais stocké) par [EventModel.statusAt].
enum EventDisplayStatus { cancelled, finished, ongoing, full, upcoming }

/// Modèle "Gestion des Événements".
///
/// Les dates sont stockées en Timestamp (instant UTC) et manipulées en heure
/// locale dans l'app.
class EventModel {
  /// Durée appliquée aux anciens documents qui n'ont pas de date de fin.
  static const Duration defaultDuration = Duration(hours: 2);

  final String id;
  final String organizerId;
  final String organizerName;
  final String title;
  final String description;
  final String category;
  final DateTime startDate;
  final DateTime endDate;
  final String location;
  final double? latitude;
  final double? longitude;
  final List<String> registeredUserIds;
  final String? posterUrl;
  final int? capacity; // null = places illimitées
  final EventStatus status;
  final String? cancelReason;
  final DateTime? cancelledAt;
  final List<String> checkedInUserIds;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool pendingSync;

  /// [endDate], [createdAt] et [updatedAt] sont optionnels : par défaut
  /// fin = début + 2 h, création = modification = début (anciens documents).
  EventModel({
    required this.id,
    required this.organizerId,
    required this.organizerName,
    required this.title,
    required this.description,
    required this.category,
    required this.startDate,
    DateTime? endDate,
    required this.location,
    this.latitude,
    this.longitude,
    this.registeredUserIds = const [],
    this.posterUrl,
    this.capacity,
    this.status = EventStatus.active,
    this.cancelReason,
    this.cancelledAt,
    this.checkedInUserIds = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
    this.pendingSync = false,
  })  : endDate = endDate ?? startDate.add(defaultDuration),
        createdAt = createdAt ?? startDate,
        updatedAt = updatedAt ?? startDate;

  bool isUserRegistered(String userId) => registeredUserIds.contains(userId);

  /// Complet : une capacité est définie et elle est atteinte.
  bool get isFull => capacity != null && registeredUserIds.length >= capacity!;

  /// Statut affiché à l'instant [now] (fonction pure : même entrée, même
  /// résultat, pas d'horloge cachée — donc testable).
  /// Ordre de priorité : annulé > terminé > en cours > complet > à venir.
  EventDisplayStatus statusAt(DateTime now) {
    if (status == EventStatus.cancelled) return EventDisplayStatus.cancelled;
    if (!now.isBefore(endDate)) return EventDisplayStatus.finished; // now >= fin
    if (!now.isBefore(startDate)) return EventDisplayStatus.ongoing; // début <= now < fin
    if (isFull) return EventDisplayStatus.full;
    return EventDisplayStatus.upcoming;
  }

  factory EventModel.fromMap(String id, Map<String, dynamic> map) {
    // Lectures « null-aware » : un ancien document sans les nouveaux champs
    // se charge quand même avec les valeurs par défaut.
    final start = _parseDate(map['startDate']) ?? DateTime.now();
    return EventModel(
      id: id,
      organizerId: map['organizerId'] ?? '',
      organizerName: map['organizerName'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      category: map['category'] ?? 'Générale',
      startDate: start,
      endDate: _parseDate(map['endDate']),
      location: map['location'] ?? '',
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      registeredUserIds: List<String>.from(map['registeredUserIds'] ?? []),
      posterUrl: map['posterUrl'],
      capacity: (map['capacity'] as num?)?.toInt(),
      status: map['status'] == EventStatus.cancelled.name ? EventStatus.cancelled : EventStatus.active,
      cancelReason: map['cancelReason'],
      cancelledAt: _parseDate(map['cancelledAt']),
      checkedInUserIds: List<String>.from(map['checkedInUserIds'] ?? []),
      createdAt: _parseDate(map['createdAt']),
      updatedAt: _parseDate(map['updatedAt']),
    );
  }

  /// Une date peut arriver sous 4 formes : Timestamp (Firestore), DateTime
  /// (cache Hive), int (millisecondes) ou String (ISO 8601). Toujours rendue
  /// en heure locale ; null si absente ou illisible.
  static DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate().toLocal();
    if (value is DateTime) return value.toLocal();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }

  Map<String, dynamic> toMap() {
    return {
      'organizerId': organizerId,
      'organizerName': organizerName,
      'title': title,
      'description': description,
      'category': category,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'location': location,
      'latitude': latitude,
      'longitude': longitude,
      'registeredUserIds': registeredUserIds,
      'posterUrl': posterUrl,
      'capacity': capacity,
      'status': status.name,
      'cancelReason': cancelReason,
      'cancelledAt': cancelledAt == null ? null : Timestamp.fromDate(cancelledAt!),
      'checkedInUserIds': checkedInUserIds,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  /// Copie avec certains champs changés. Pour remettre la capacité à
  /// « illimitée » (null), passer [clearCapacity] à true.
  EventModel copyWith({
    String? id,
    String? organizerName,
    String? title,
    String? description,
    String? category,
    DateTime? startDate,
    DateTime? endDate,
    String? location,
    double? latitude,
    double? longitude,
    List<String>? registeredUserIds,
    String? posterUrl,
    int? capacity,
    bool clearCapacity = false,
    EventStatus? status,
    String? cancelReason,
    DateTime? cancelledAt,
    List<String>? checkedInUserIds,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? pendingSync,
  }) {
    return EventModel(
      id: id ?? this.id,
      organizerId: organizerId, // ne change jamais
      organizerName: organizerName ?? this.organizerName,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      location: location ?? this.location,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      registeredUserIds: registeredUserIds ?? this.registeredUserIds,
      posterUrl: posterUrl ?? this.posterUrl,
      capacity: clearCapacity ? null : (capacity ?? this.capacity),
      status: status ?? this.status,
      cancelReason: cancelReason ?? this.cancelReason,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      checkedInUserIds: checkedInUserIds ?? this.checkedInUserIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      pendingSync: pendingSync ?? this.pendingSync,
    );
  }

  /// Copie avec l'utilisateur ajouté ou retiré des inscrits ; tous les
  /// autres champs sont conservés.
  EventModel copyWithRegistration(String userId, bool register) {
    final updated = List<String>.from(registeredUserIds);
    if (register) {
      if (!updated.contains(userId)) updated.add(userId);
    } else {
      updated.remove(userId);
    }
    return copyWith(registeredUserIds: updated);
  }
}
