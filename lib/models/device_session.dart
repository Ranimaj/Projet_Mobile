import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _date(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  return null;
}

/// Un appareil sur lequel le compte s'est connecté
/// (`users/{uid}/devices/{deviceId}`). L'identifiant est tiré au hasard à la
/// première ouverture de l'app et gardé sur le téléphone.
class DeviceSession {
  final String id;

  /// Modèle lisible, p. ex. « Samsung Galaxy S23 » ou « iPhone 15 ».
  final String name;

  /// `android`, `ios`, `macos`…
  final String platform;

  /// Ville approximative de la dernière connexion (si la position est déjà
  /// autorisée sur le téléphone), sinon `null`.
  final String? location;

  final DateTime? firstLoginAt;
  final DateTime? lastLoginAt;
  final DateTime? lastSeenAt;

  /// Appareil de confiance : une connexion ici ne redemande pas le code SMS
  /// quand la double authentification est active.
  final bool trusted;

  /// Session fermée à distance depuis un autre appareil.
  final bool revoked;

  /// Session fermée par l'utilisateur sur cet appareil (« Se déconnecter »).
  final bool signedOut;

  /// Nouvel appareil que l'utilisateur n'a pas encore confirmé (« C'est
  /// moi ») depuis un autre appareil.
  final bool alertPending;

  const DeviceSession({
    required this.id,
    required this.name,
    required this.platform,
    this.location,
    this.firstLoginAt,
    this.lastLoginAt,
    this.lastSeenAt,
    this.trusted = false,
    this.revoked = false,
    this.signedOut = false,
    this.alertPending = false,
  });

  /// La session est ouverte sur cet appareil.
  bool get isActive => !revoked && !signedOut;

  factory DeviceSession.fromMap(String id, Map<String, dynamic> map) => DeviceSession(
        id: id,
        name: map['name'] as String? ?? 'Appareil inconnu',
        platform: map['platform'] as String? ?? '',
        location: map['location'] as String?,
        firstLoginAt: _date(map['firstLoginAt']),
        lastLoginAt: _date(map['lastLoginAt']),
        lastSeenAt: _date(map['lastSeenAt']),
        trusted: map['trusted'] == true,
        revoked: map['revoked'] == true,
        signedOut: map['signedOut'] == true,
        alertPending: map['alertPending'] == true,
      );
}

/// Une connexion enregistrée (`users/{uid}/logins/{id}`).
class LoginRecord {
  final String id;
  final String deviceId;
  final String deviceName;
  final String? location;
  final DateTime? at;

  /// Première connexion depuis cet appareil.
  final bool newDevice;

  const LoginRecord({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    this.location,
    this.at,
    this.newDevice = false,
  });

  factory LoginRecord.fromMap(String id, Map<String, dynamic> map) => LoginRecord(
        id: id,
        deviceId: map['deviceId'] as String? ?? '',
        deviceName: map['deviceName'] as String? ?? 'Appareil inconnu',
        location: map['location'] as String?,
        at: _date(map['at']),
        newDevice: map['newDevice'] == true,
      );
}
