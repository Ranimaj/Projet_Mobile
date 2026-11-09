import 'package:campusconnect/services/device_session_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Un « téléphone » : son propre stockage local, la même base Firestore.
DeviceSessionService phone(FakeFirebaseFirestore db, String name, {String? city}) {
  SharedPreferences.setMockInitialValues({});
  final prefs = SharedPreferences.getInstance();
  return DeviceSessionService(
    firestore: db,
    deviceInfo: () async => (name: name, platform: 'android'),
    city: () async => city,
    prefs: () => prefs,
  );
}

void main() {
  late FakeFirebaseFirestore db;
  setUp(() => db = FakeFirebaseFirestore());

  Future<List<Map<String, dynamic>>> logins() async =>
      [for (final d in (await db.collection('users/u1/logins').get()).docs) d.data()];

  test('first login records the device and the login, without alert', () async {
    final a = phone(db, 'Pixel 8', city: 'Tunis, Tunisie');
    final r = await a.onSignedIn('u1', twoFactor: false);
    expect(r.newDevice, isTrue);
    expect(r.needsConfirmation, isFalse);

    final devices = await a.watchDevices('u1').first;
    expect(devices.single.name, 'Pixel 8');
    expect(devices.single.location, 'Tunis, Tunisie');
    expect(devices.single.trusted, isTrue);
    expect(devices.single.alertPending, isFalse);
    expect((await logins()).single['newDevice'], isTrue);
  });

  test('a second device raises the new-device alert', () async {
    await phone(db, 'Pixel 8').onSignedIn('u1', twoFactor: false);
    final b = phone(db, 'iPhone 15');
    await b.onSignedIn('u1', twoFactor: false);

    final devices = await b.watchDevices('u1').first;
    final iphone = devices.firstWhere((d) => d.name == 'iPhone 15');
    expect(iphone.alertPending, isTrue);
    await b.acknowledge('u1', iphone.id);
    expect((await b.watchDevices('u1').first).firstWhere((d) => d.name == 'iPhone 15').alertPending, isFalse);
  });

  test('a restored session is not a new login', () async {
    final a = phone(db, 'Pixel 8');
    await a.onSignedIn('u1', twoFactor: false);
    final again = await a.onSignedIn('u1', twoFactor: false);
    expect(again.newDevice, isFalse);
    expect(await logins(), hasLength(1));
  });

  test('2FA: a new device needs confirmation, then becomes trusted', () async {
    await phone(db, 'Pixel 8').onSignedIn('u1', twoFactor: true);
    final b = phone(db, 'iPhone 15');
    final r = await b.onSignedIn('u1', twoFactor: true);
    expect(r.needsConfirmation, isTrue);
    // Restauration avant confirmation : toujours à confirmer.
    expect((await b.onSignedIn('u1', twoFactor: true)).needsConfirmation, isTrue);

    await b.confirmThisDevice('u1');
    expect((await b.onSignedIn('u1', twoFactor: true)).needsConfirmation, isFalse);
  });

  test('a revoked device is told to sign out, and must confirm again later', () async {
    final a = phone(db, 'Pixel 8');
    await a.onSignedIn('u1', twoFactor: true);
    final b = phone(db, 'iPhone 15');
    await b.onSignedIn('u1', twoFactor: true);
    await b.confirmThisDevice('u1');
    final bId = (await b.currentDevice()).id;

    await a.revoke('u1', bId);
    expect((await b.onSignedIn('u1', twoFactor: true)).revoked, isTrue);
    expect((await b.watchThisDevice('u1').first)!.revoked, isTrue);

    // Nouvelle connexion sur l'iPhone : la session redémarre, à confirmer.
    await b.forgetLocalSession();
    final r = await b.onSignedIn('u1', twoFactor: true);
    expect(r.revoked, isFalse);
    expect(r.needsConfirmation, isTrue);
  });

  test('revokeOthers closes every other active session', () async {
    final a = phone(db, 'Pixel 8');
    await a.onSignedIn('u1', twoFactor: false);
    await phone(db, 'iPhone 15').onSignedIn('u1', twoFactor: false);
    await phone(db, 'MacBook').onSignedIn('u1', twoFactor: false);

    expect(await a.revokeOthers('u1'), 2);
    final devices = await a.watchDevices('u1').first;
    expect(devices.where((d) => d.isActive).single.name, 'Pixel 8');
  });

  test('sign-out, export and delete', () async {
    final a = phone(db, 'Pixel 8');
    await a.onSignedIn('u1', twoFactor: false);
    await a.onSignedOut('u1');
    expect((await a.watchThisDevice('u1').first)!.signedOut, isTrue);

    final export = await a.export('u1');
    expect((export['devices'] as List).single['name'], 'Pixel 8');
    expect(export['logins'] as List, hasLength(1));

    await a.deleteAll('u1');
    expect((await db.collection('users/u1/devices').get()).docs, isEmpty);
    expect((await db.collection('users/u1/logins').get()).docs, isEmpty);
  });

  test('a failing city lookup does not block the login', () async {
    SharedPreferences.setMockInitialValues({});
    final s = DeviceSessionService(
      firestore: db,
      deviceInfo: () async => (name: 'Pixel 8', platform: 'android'),
      city: () async => throw Exception('no GPS'),
    );
    await s.onSignedIn('u1', twoFactor: false);
    expect((await s.watchThisDevice('u1').first)!.location, isNull);
  });
}
