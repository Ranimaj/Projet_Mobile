import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/device_session.dart';

/// Ce que l'app sait de l'appareil courant.
class DeviceInfo {
  final String id;
  final String name;
  final String platform;
  const DeviceInfo({required this.id, required this.name, required this.platform});
}

/// Résultat de l'ouverture de session sur cet appareil.
class SignInOutcome {
  /// Premier passage du compte sur cet appareil.
  final bool newDevice;

  /// Double authentification active et appareil pas encore de confiance :
  /// un code SMS doit confirmer la connexion.
  final bool needsConfirmation;

  /// La session a été fermée à distance pendant que l'app était fermée.
  final bool revoked;

  const SignInOutcome({this.newDevice = false, this.needsConfirmation = false, this.revoked = false});
}

typedef DeviceInfoLookup = Future<({String name, String platform})> Function();
typedef CityLookup = Future<String?> Function();

/// Appareils et historique des connexions d'un compte
/// (`users/{uid}/devices` et `users/{uid}/logins`).
///
/// Chaque appareil écoute son propre document : quand un autre appareil le
/// marque `revoked`, il ferme sa session. Les règles Firestore limitent ces
/// documents à leur propriétaire (et aux admins en lecture).
class DeviceSessionService {
  DeviceSessionService({
    required FirebaseFirestore firestore,
    DeviceInfoLookup? deviceInfo,
    CityLookup? city,
    Future<SharedPreferences> Function()? prefs,
  })  : _db = firestore,
        _deviceInfo = deviceInfo ?? _platformDeviceInfo,
        _city = city ?? _approximateCity,
        _prefs = prefs ?? SharedPreferences.getInstance;

  final FirebaseFirestore _db;
  final DeviceInfoLookup _deviceInfo;
  final CityLookup _city;
  final Future<SharedPreferences> Function() _prefs;

  static const _deviceIdKey = 'device_id';
  static const _sessionUidKey = 'device_session_uid';

  /// Nombre de connexions montrées dans l'historique.
  static const historyLength = 20;

  CollectionReference<Map<String, dynamic>> _devices(String uid) =>
      _db.collection('users').doc(uid).collection('devices');
  CollectionReference<Map<String, dynamic>> _logins(String uid) =>
      _db.collection('users').doc(uid).collection('logins');

  DeviceInfo? _info;

  /// Identifiant de cet appareil, tiré une fois et gardé sur le téléphone.
  Future<DeviceInfo> currentDevice() async {
    final cached = _info;
    if (cached != null) return cached;
    final prefs = await _prefs();
    var id = prefs.getString(_deviceIdKey);
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString(_deviceIdKey, id);
    }
    final d = await _deviceInfo();
    return _info = DeviceInfo(id: id, name: d.name, platform: d.platform);
  }

  /// À appeler dès que Firebase annonce une session ouverte, que ce soit
  /// une vraie connexion ou une session restaurée au lancement de l'app.
  Future<SignInOutcome> onSignedIn(String uid, {required bool twoFactor}) async {
    final device = await currentDevice();
    final prefs = await _prefs();
    final ref = _devices(uid).doc(device.id);
    final snap = await ref.get();
    final existing = snap.exists ? DeviceSession.fromMap(snap.id, snap.data()!) : null;

    // Session restaurée : l'app a déjà enregistré ce compte sur ce téléphone.
    if (prefs.getString(_sessionUidKey) == uid && existing != null) {
      if (existing.revoked) return const SignInOutcome(revoked: true);
      await ref.update({'lastSeenAt': FieldValue.serverTimestamp()});
      return SignInOutcome(needsConfirmation: twoFactor && !existing.trusted);
    }

    // Vraie connexion.
    final newDevice = existing == null;
    final needsConfirmation = twoFactor && !(existing?.trusted ?? false);
    final others = newDevice ? await _devices(uid).limit(1).get() : null;
    final location = await _safeCity();
    final now = FieldValue.serverTimestamp();
    await ref.set({
      'name': device.name,
      'platform': device.platform,
      'location': location,
      if (newDevice) 'firstLoginAt': now,
      'lastLoginAt': now,
      'lastSeenAt': now,
      'trusted': (existing?.trusted ?? false) || !needsConfirmation,
      'revoked': false,
      'signedOut': false,
      // Les autres appareils affichent l'alerte « Nouvelle connexion ».
      'alertPending': newDevice && (others?.docs.isNotEmpty ?? false),
    }, SetOptions(merge: true));
    await _logins(uid).add({
      'deviceId': device.id,
      'deviceName': device.name,
      'location': location,
      'at': now,
      'newDevice': newDevice,
    });
    await prefs.setString(_sessionUidKey, uid);
    return SignInOutcome(newDevice: newDevice, needsConfirmation: needsConfirmation);
  }

  Future<String?> _safeCity() async {
    try {
      return await _city().timeout(const Duration(seconds: 5));
    } catch (_) {
      return null;
    }
  }

  /// Déconnexion volontaire sur cet appareil.
  Future<void> onSignedOut(String uid) async {
    try {
      final device = await currentDevice();
      await _devices(uid).doc(device.id).update({'signedOut': true});
    } catch (_) {
      // Hors-ligne ou document absent : rien de grave.
    }
    await forgetLocalSession();
  }

  /// Oublie la session locale (après une fermeture à distance).
  Future<void> forgetLocalSession() async {
    try {
      final prefs = await _prefs();
      await prefs.remove(_sessionUidKey);
    } catch (_) {}
  }

  /// Document de cet appareil, en direct.
  Stream<DeviceSession?> watchThisDevice(String uid) async* {
    final device = await currentDevice();
    yield* _devices(uid).doc(device.id).snapshots().map(
        (s) => s.exists ? DeviceSession.fromMap(s.id, s.data()!) : null);
  }

  /// Tous les appareils, le plus récemment connecté d'abord.
  Stream<List<DeviceSession>> watchDevices(String uid) =>
      _devices(uid).orderBy('lastLoginAt', descending: true).snapshots().map(
          (s) => [for (final d in s.docs) DeviceSession.fromMap(d.id, d.data())]);

  /// Dernières connexions, la plus récente d'abord.
  Stream<List<LoginRecord>> watchLogins(String uid) => _logins(uid)
      .orderBy('at', descending: true)
      .limit(historyLength)
      .snapshots()
      .map((s) => [for (final d in s.docs) LoginRecord.fromMap(d.id, d.data())]);

  /// Le code SMS a confirmé cette connexion : l'appareil devient de confiance.
  Future<void> confirmThisDevice(String uid) async {
    final device = await currentDevice();
    await _devices(uid).doc(device.id).update({'trusted': true});
  }

  /// « C'est bien moi » : l'alerte de nouvelle connexion disparaît.
  Future<void> acknowledge(String uid, String deviceId) =>
      _devices(uid).doc(deviceId).update({'alertPending': false});

  Future<void> setTrusted(String uid, String deviceId, bool trusted) =>
      _devices(uid).doc(deviceId).update({'trusted': trusted});

  /// Ferme la session d'un appareil à distance. Il n'est plus de confiance :
  /// avec la double authentification, la prochaine connexion redemandera le
  /// code SMS.
  Future<void> revoke(String uid, String deviceId) => _devices(uid).doc(deviceId).update({
        'revoked': true,
        'trusted': false,
        'alertPending': false,
      });

  /// Ferme toutes les sessions sauf celle de cet appareil.
  Future<int> revokeOthers(String uid) async {
    final me = (await currentDevice()).id;
    final snap = await _devices(uid).get();
    final batch = _db.batch();
    var count = 0;
    for (final d in snap.docs) {
      final s = DeviceSession.fromMap(d.id, d.data());
      if (d.id == me || !s.isActive) continue;
      batch.update(d.reference, {'revoked': true, 'trusted': false, 'alertPending': false});
      count++;
    }
    await batch.commit();
    return count;
  }

  /// Pour l'export RGPD.
  Future<Map<String, dynamic>> export(String uid) async {
    final devices = await _devices(uid).get();
    final logins = await _logins(uid).orderBy('at', descending: true).get();
    String? iso(dynamic v) => v is Timestamp ? v.toDate().toIso8601String() : null;
    return {
      'devices': [
        for (final d in devices.docs)
          {
            for (final e in d.data().entries) e.key: e.value is Timestamp ? iso(e.value) : e.value,
            'id': d.id,
          },
      ],
      'logins': [
        for (final d in logins.docs)
          {
            for (final e in d.data().entries) e.key: e.value is Timestamp ? iso(e.value) : e.value,
          },
      ],
    };
  }

  /// Efface appareils et historique (suppression du compte).
  Future<void> deleteAll(String uid) async {
    for (final col in [_devices(uid), _logins(uid)]) {
      final snap = await col.get();
      for (final d in snap.docs) {
        await d.reference.delete();
      }
    }
    await forgetLocalSession();
  }
}

Future<({String name, String platform})> _platformDeviceInfo() async {
  final plugin = DeviceInfoPlugin();
  try {
    if (Platform.isAndroid) {
      final a = await plugin.androidInfo;
      final brand = a.manufacturer.isEmpty
          ? ''
          : '${a.manufacturer[0].toUpperCase()}${a.manufacturer.substring(1)} ';
      return (name: '$brand${a.model}'.trim(), platform: 'android');
    }
    if (Platform.isIOS) {
      final i = await plugin.iosInfo;
      return (name: i.modelName.isEmpty ? i.model : i.modelName, platform: 'ios');
    }
    if (Platform.isMacOS) {
      final m = await plugin.macOsInfo;
      return (name: m.modelName.isEmpty ? m.model : m.modelName, platform: 'macos');
    }
  } catch (_) {}
  return (name: Platform.operatingSystem, platform: Platform.operatingSystem);
}

/// Ville approximative, seulement si la position est **déjà** autorisée :
/// la connexion ne déclenche jamais de demande de permission.
Future<String?> _approximateCity() async {
  final permission = await Geolocator.checkPermission();
  if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) {
    return null;
  }
  final pos = await Geolocator.getLastKnownPosition() ??
      await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
      );
  final places = await placemarkFromCoordinates(pos.latitude, pos.longitude);
  if (places.isEmpty) return null;
  final p = places.first;
  return [p.locality, p.country].where((e) => e != null && e.isNotEmpty).join(', ');
}
