import 'dart:convert';

import 'package:campusconnect/core/utils/local_database.dart';
import 'package:campusconnect/services/device_session_service.dart';
import 'package:campusconnect/services/local_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/local_db.dart';

void main() {
  late LocalStore store;
  late DateTime now;

  DeviceSessionService phone({String name = 'Pixel 8', String? city}) => DeviceSessionService(
        store: store,
        deviceInfo: () async => (name: name, platform: 'android'),
        city: () async => city,
        clock: () => now,
      );

  setUp(() async {
    await openTestDatabase();
    store = LocalStore();
    now = DateTime(2026, 11, 9, 10);
  });
  tearDown(closeTestDatabase);

  test('first login records this phone and the login', () async {
    final s = phone(city: 'Tunis, Tunisie');
    await s.recordLogin('u1');

    final device = (await s.watchThisDevice('u1').first)!;
    expect(device.name, 'Pixel 8');
    expect(device.platform, 'android');
    expect(device.location, 'Tunis, Tunisie');
    expect(device.firstLoginAt, now);
    expect(device.lastLoginAt, now);
    expect(device.isActive, isTrue);

    final logins = await s.watchLogins('u1').first;
    expect(logins.single.deviceName, 'Pixel 8');
    expect(logins.single.location, 'Tunis, Tunisie');
    expect(logins.single.newDevice, isTrue);
  });

  test('the phone id is drawn once and kept in the local settings', () async {
    final id = (await phone().currentDevice()).id;
    expect(store.getValue(DeviceSessionService.deviceIdKey), id);
    // Un autre service (redémarrage de l'app) retrouve le même identifiant.
    expect((await phone().currentDevice()).id, id);
  });

  test('a second login updates this phone and adds to the history, newest first', () async {
    final s = phone();
    await s.recordLogin('u1');
    final first = now;
    now = now.add(const Duration(hours: 2));
    await s.recordLogin('u1');

    final device = (await s.watchThisDevice('u1').first)!;
    expect(device.firstLoginAt, first);
    expect(device.lastLoginAt, now);
    expect(store.all(DeviceSessionService.devicesCollection), hasLength(1));

    final logins = await s.watchLogins('u1').first;
    expect([for (final l in logins) l.at], [now, first]);
    expect([for (final l in logins) l.newDevice], [false, true]);
  });

  test('history is per account and limited to the last 20', () async {
    final s = phone();
    for (var i = 0; i < 25; i++) {
      now = now.add(const Duration(minutes: 1));
      await s.recordLogin('u1');
    }
    await s.recordLogin('u2');

    final logins = await s.watchLogins('u1').first;
    expect(logins, hasLength(DeviceSessionService.historyLength));
    expect(logins.first.at, now);
    expect(logins.last.at, now.subtract(const Duration(minutes: 19)));
    expect(logins.every((l) => l.uid == 'u1'), isTrue);
    expect(await s.watchLogins('u2').first, hasLength(1));
  });

  test('the history stream follows new logins', () async {
    final s = phone();
    final seen = <int>[];
    final sub = s.watchLogins('u1').listen((l) => seen.add(l.length));
    await pumpEventQueue();
    await s.recordLogin('u1');
    await pumpEventQueue();
    await sub.cancel();
    expect(seen.first, 0);
    expect(seen.last, 1);
  });

  test('logout marks this phone as signed out, the next login reopens it', () async {
    final s = phone();
    await s.recordLogin('u1');
    now = now.add(const Duration(hours: 1));
    await s.recordLogout('u1');
    var device = (await s.watchThisDevice('u1').first)!;
    expect(device.signedOut, isTrue);
    expect(device.lastLogoutAt, now);

    await s.recordLogin('u1');
    device = (await s.watchThisDevice('u1').first)!;
    expect(device.isActive, isTrue);
  });

  test('logout before any login does nothing', () async {
    await phone().recordLogout('u1');
    expect(store.all(DeviceSessionService.devicesCollection), isEmpty);
  });

  test('export is JSON-safe; deleteAll only erases this account', () async {
    final s = phone();
    await s.recordLogin('u1');
    await s.recordLogin('u2');

    final export = await s.export('u1');
    expect(() => jsonEncode(export), returnsNormally);
    expect((export['devices'] as List).single['name'], 'Pixel 8');
    expect((export['devices'] as List).single['lastLoginAt'], now.toUtc().toIso8601String());
    expect(export['logins'] as List, hasLength(1));

    await s.deleteAll('u1');
    expect(await s.watchLogins('u1').first, isEmpty);
    expect(await s.watchThisDevice('u1').first, isNull);
    expect(await s.watchLogins('u2').first, hasLength(1));
  });

  test('a failing city or device lookup does not block the login', () async {
    final s = DeviceSessionService(
      store: store,
      deviceInfo: () async => throw Exception('no plugin'),
      city: () async => throw Exception('no GPS'),
      clock: () => now,
    );
    await s.recordLogin('u1');
    final device = (await s.watchThisDevice('u1').first)!;
    expect(device.location, isNull);
    expect(device.name, 'Ce téléphone');
  });

  test('without an open database the default constructor throws', () async {
    await closeTestDatabase();
    expect(LocalDatabase.isOpen, isFalse);
    expect(() => DeviceSessionService(), throwsStateError);
  });
}
