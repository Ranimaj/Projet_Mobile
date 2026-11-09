import '../services/local_store.dart' show parseDate;

/// Ce téléphone, vu par un compte (collection `devices`, un document par
/// compte connecté sur ce téléphone). L'identifiant du téléphone est tiré au
/// hasard à la première connexion et gardé dans les réglages locaux.
///
/// Tout reste sur le téléphone : l'app ne voit aucun autre appareil.
class DeviceSession {
  /// Identifiant du document (`{uid}_{deviceId}`).
  final String id;

  final String uid;
  final String deviceId;

  /// Modèle lisible, p. ex. « Samsung Galaxy S23 » ou « iPhone 15 ».
  final String name;

  /// `android`, `ios`, `macos`…
  final String platform;

  /// Ville approximative de la dernière connexion (si la position est déjà
  /// autorisée sur le téléphone), sinon `null`.
  final String? location;

  /// Première connexion du compte sur ce téléphone.
  final DateTime? firstLoginAt;

  /// Dernière connexion par mot de passe : début de la session en cours.
  final DateTime? lastLoginAt;

  /// Dernière déconnexion volontaire.
  final DateTime? lastLogoutAt;

  /// La dernière session a été fermée (« Se déconnecter »).
  final bool signedOut;

  const DeviceSession({
    required this.id,
    required this.uid,
    required this.deviceId,
    required this.name,
    required this.platform,
    this.location,
    this.firstLoginAt,
    this.lastLoginAt,
    this.lastLogoutAt,
    this.signedOut = false,
  });

  /// La session est ouverte sur ce téléphone.
  bool get isActive => !signedOut;

  factory DeviceSession.fromMap(String id, Map<String, dynamic> map) => DeviceSession(
        id: id,
        uid: map['uid'] as String? ?? '',
        deviceId: map['deviceId'] as String? ?? '',
        name: map['name'] as String? ?? 'Appareil inconnu',
        platform: map['platform'] as String? ?? '',
        location: map['location'] as String?,
        firstLoginAt: parseDate(map['firstLoginAt']),
        lastLoginAt: parseDate(map['lastLoginAt']),
        lastLogoutAt: parseDate(map['lastLogoutAt']),
        signedOut: map['signedOut'] == true,
      );
}

/// Une connexion par mot de passe enregistrée sur ce téléphone (collection
/// `logins`).
class LoginRecord {
  final String id;
  final String uid;
  final String deviceId;
  final String deviceName;
  final String platform;
  final String? location;
  final DateTime? at;

  /// Première connexion du compte sur ce téléphone.
  final bool newDevice;

  const LoginRecord({
    required this.id,
    required this.uid,
    required this.deviceId,
    required this.deviceName,
    this.platform = '',
    this.location,
    this.at,
    this.newDevice = false,
  });

  factory LoginRecord.fromMap(String id, Map<String, dynamic> map) => LoginRecord(
        id: id,
        uid: map['uid'] as String? ?? '',
        deviceId: map['deviceId'] as String? ?? '',
        deviceName: map['deviceName'] as String? ?? 'Appareil inconnu',
        platform: map['platform'] as String? ?? '',
        location: map['location'] as String?,
        at: parseDate(map['at']),
        newDevice: map['newDevice'] == true,
      );
}
