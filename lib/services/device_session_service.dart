import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../core/utils/local_database.dart';
import '../models/device_session.dart';
import 'local_store.dart';

/// Ce que l'app sait de ce téléphone.
class DeviceInfo {
  final String id;
  final String name;
  final String platform;
  const DeviceInfo({required this.id, required this.name, required this.platform});
}

typedef DeviceInfoLookup = Future<({String name, String platform})> Function();
typedef CityLookup = Future<String?> Function();

/// « Mes appareils » : ce téléphone et l'historique des connexions de chaque
/// compte sur ce téléphone (collections `devices` et `logins` de
/// [LocalStore]).
///
/// Il n'y a pas de serveur : l'app ne voit ni ne contrôle aucun autre
/// appareil, et ces données ne quittent jamais le téléphone.
class DeviceSessionService {
  /// Lève une [StateError] si la base locale n'est pas ouverte et qu'aucun
  /// [store] n'est fourni (l'AuthProvider se passe alors de l'historique).
  DeviceSessionService({
    LocalStore? store,
    DeviceInfoLookup? deviceInfo,
    CityLookup? city,
    DateTime Function()? clock,
  })  : _store = store ?? _sharedStore(),
        _deviceInfo = deviceInfo ?? _platformDeviceInfo,
        _city = city ?? _approximateCity,
        _now = clock ?? DateTime.now;

  static LocalStore _sharedStore() {
    if (!LocalDatabase.isOpen) throw StateError('Stockage local indisponible');
    return LocalStore();
  }

  final LocalStore _store;
  final DeviceInfoLookup _deviceInfo;
  final CityLookup _city;
  final DateTime Function() _now;

  static const devicesCollection = 'devices';
  static const loginsCollection = 'logins';

  /// Réglage local qui garde l'identifiant de ce téléphone.
  static const deviceIdKey = 'device.id';

  /// Nombre de connexions montrées dans l'historique.
  static const historyLength = 20;

  DeviceInfo? _info;

  static String _docId(String uid, String deviceId) => '${uid}_$deviceId';

  /// Ce téléphone : identifiant tiré une fois et gardé dans les réglages.
  Future<DeviceInfo> currentDevice() async {
    final cached = _info;
    if (cached != null) return cached;
    var id = _store.getValue(deviceIdKey);
    if (id == null) {
      id = LocalStore.newId();
      await _store.setValue(deviceIdKey, id);
    }
    ({String name, String platform}) d;
    try {
      d = await _deviceInfo();
    } catch (_) {
      d = (name: 'Ce téléphone', platform: '');
    }
    return _info = DeviceInfo(id: id, name: d.name, platform: d.platform);
  }

  /// Connexion par mot de passe (ou inscription) : ajoute une ligne à
  /// l'historique et met à jour la fiche de ce téléphone pour [uid].
  Future<void> recordLogin(String uid) async {
    final device = await currentDevice();
    final location = await _safeCity();
    final now = _now();
    final id = _docId(uid, device.id);
    final newDevice = !_store.exists(devicesCollection, id);
    await _store.merge(devicesCollection, id, {
      'uid': uid,
      'deviceId': device.id,
      'name': device.name,
      'platform': device.platform,
      'location': location,
      if (newDevice) 'firstLoginAt': now,
      'lastLoginAt': now,
      'signedOut': false,
    });
    await _store.set(loginsCollection, LocalStore.newId(), {
      'uid': uid,
      'deviceId': device.id,
      'deviceName': device.name,
      'platform': device.platform,
      'location': location,
      'at': now,
      'newDevice': newDevice,
    });
  }

  Future<String?> _safeCity() async {
    try {
      return await _city().timeout(const Duration(seconds: 5));
    } catch (_) {
      return null;
    }
  }

  /// Déconnexion volontaire sur ce téléphone.
  Future<void> recordLogout(String uid) async {
    final device = await currentDevice();
    final id = _docId(uid, device.id);
    if (!_store.exists(devicesCollection, id)) return;
    await _store.update(devicesCollection, id, {'signedOut': true, 'lastLogoutAt': _now()});
  }

  /// Fiche de ce téléphone pour [uid] (null avant la première connexion),
  /// en direct.
  Stream<DeviceSession?> watchThisDevice(String uid) async* {
    final device = await currentDevice();
    final id = _docId(uid, device.id);
    yield* _store.watchDoc(devicesCollection, id).map((data) => data == null ? null : DeviceSession.fromMap(id, data));
  }

  /// Dernières connexions de [uid] sur ce téléphone, la plus récente
  /// d'abord ([historyLength] au plus).
  Stream<List<LoginRecord>> watchLogins(String uid) =>
      _store.watch(loginsCollection).map((_) => _logins(uid).take(historyLength).toList());

  List<LoginRecord> _logins(String uid) {
    final list = [
      for (final d in _store.where(loginsCollection, (m) => m['uid'] == uid)) LoginRecord.fromMap(d.id, d.data),
    ];
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    list.sort((a, b) => (b.at ?? epoch).compareTo(a.at ?? epoch));
    return list;
  }

  /// Pour l'export RGPD (valeurs JSON : les dates en ISO 8601).
  Future<Map<String, dynamic>> export(String uid) async => {
        'devices': [
          for (final d in _store.where(devicesCollection, (m) => m['uid'] == uid)) {..._jsonSafe(d.data), 'id': d.id},
        ],
        'logins': [
          for (final l in _logins(uid)) _jsonSafe(_store.get(loginsCollection, l.id) ?? const {}),
        ],
      };

  static Map<String, dynamic> _jsonSafe(Map<String, dynamic> data) => {
        for (final e in data.entries)
          e.key: e.value is DateTime ? (e.value as DateTime).toUtc().toIso8601String() : e.value,
      };

  /// Efface la fiche et l'historique de [uid] (suppression du compte).
  Future<void> deleteAll(String uid) async {
    await _store.deleteWhere(devicesCollection, (m) => m['uid'] == uid);
    await _store.deleteWhere(loginsCollection, (m) => m['uid'] == uid);
  }
}

Future<({String name, String platform})> _platformDeviceInfo() async {
  final plugin = DeviceInfoPlugin();
  try {
    if (Platform.isAndroid) {
      final a = await plugin.androidInfo;
      final brand = a.manufacturer.isEmpty ? '' : '${a.manufacturer[0].toUpperCase()}${a.manufacturer.substring(1)} ';
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
