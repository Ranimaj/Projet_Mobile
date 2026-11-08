import 'dart:io';

import 'package:campusconnect/core/utils/local_database.dart';
import 'package:campusconnect/services/login_prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/local_db.dart';

void main() {
  late Directory dir;
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('login_prefs_test');
    path = p.join(dir.path, 'prefs.db');
  });

  tearDown(() async {
    await closeTestDatabase();
    await dir.delete(recursive: true);
  });

  test('stockage non ouvert : lecture null, écriture ignorée', () async {
    final prefs = SqliteLoginPrefs();
    expect(prefs.rememberedEmail, isNull);
    await prefs.remember('amel@esprit.tn'); // ne lève pas
    expect(prefs.rememberedEmail, isNull);
  });

  test('email mémorisé dans la table kv, gardé après redémarrage', () async {
    await openTestDatabase(path: path);
    await SqliteLoginPrefs().remember('amel@esprit.tn');
    expect(LocalDatabase.instance.getValue(SqliteLoginPrefs.key), 'amel@esprit.tn');

    await LocalDatabase.instance.close();
    await openTestDatabase(path: path);
    expect(SqliteLoginPrefs().rememberedEmail, 'amel@esprit.tn');
  });

  test('null ou vide : l\'email est oublié', () async {
    await openTestDatabase(path: path);
    final prefs = SqliteLoginPrefs();
    await prefs.remember('amel@esprit.tn');
    await prefs.remember(null);
    expect(prefs.rememberedEmail, isNull);
    await prefs.remember('sami@esprit.tn');
    await prefs.remember('');
    expect(prefs.rememberedEmail, isNull);
    expect(LocalDatabase.instance.getValue(SqliteLoginPrefs.key), isNull);
  });
}
