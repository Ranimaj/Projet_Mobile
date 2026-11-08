import 'dart:io';

import 'package:campusconnect/models/article_model.dart';
import 'package:campusconnect/services/sqlite/article_database.dart';
import 'package:campusconnect/services/sqlite/local_article_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/articles.dart';

void main() {
  late Directory dir;
  late LocalArticleRepository repo;

  setUpAll(sqfliteFfiInit);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('vente_don_sqlite');
    repo = LocalArticleRepository(
      openDatabase: () => ArticleDatabase.open(factory: databaseFactoryFfi, path: '${dir.path}/articles.db'),
    );
  });

  tearDown(() async {
    await (await repo.database).close();
    dir.deleteSync(recursive: true);
  });

  test('a row keeps every field of the article', () {
    final a = article('a1',
        title: 'Veste d\'hiver',
        price: null,
        imageUrls: const ['asset:assets/images/demo/veste_hiver.jpg'],
        latitude: 36.8992,
        longitude: 10.1897,
        favoritedBy: const ['u2'],
        labels: const ['jacket'],
        viewCount: 3,
        createdAt: DateTime(2026, 11, 8, 10, 30));
    expect(ArticleDatabase.fromRow(ArticleDatabase.toRow(a)).toMap(), a.toMap());
  });

  test('create, read back (newest first), with or without network', () async {
    await repo.create(article('x', title: 'Livre', createdAt: DateTime(2026, 11, 1)), isOnline: true, explicitId: 'book');
    await repo.create(article('x', title: 'Lampe', createdAt: DateTime(2026, 11, 2)), isOnline: false, explicitId: 'lamp');
    final items = await repo.fetchAll(isOnline: false);
    expect([for (final a in items) a.id], ['lamp', 'book']);
    expect(items.last.title, 'Livre');
  });

  test('a new id is generated when none is given', () async {
    final id = await repo.create(article('ignored', title: 'Chaise'), isOnline: true);
    expect(id, isNot('ignored'));
    expect((await repo.fetchAll(isOnline: true)).single.id, id);
  });

  test('update applies a patch: status, favorites, price removed, location removed', () async {
    await repo.create(article('x', title: 'Calculatrice', price: 35, latitude: 36.9, longitude: 10.2),
        isOnline: true, explicitId: 'calc');
    await repo.update('calc', {'status': 'reserved', 'favoritedBy': ['u1', 'u2']}, isOnline: true);
    await repo.update('calc', {'price': null, 'latitude': null, 'longitude': null}, isOnline: false);
    final a = (await repo.fetchAll(isOnline: true)).single;
    expect(a.status, ArticleStatus.reserved);
    expect(a.favoritedBy, ['u1', 'u2']);
    expect(a.isFree, isTrue);
    expect(a.hasLocation, isFalse);
    expect(a.title, 'Calculatrice');
  });

  test('updating a missing article does nothing', () async {
    await repo.update('nope', {'title': 'X'}, isOnline: true);
    expect(await repo.fetchAll(isOnline: true), isEmpty);
  });

  test('delete removes the row', () async {
    await repo.create(article('x'), isOnline: true, explicitId: 'a');
    await repo.delete('a', isOnline: true);
    expect(await repo.fetchAll(isOnline: true), isEmpty);
  });

  test('the data survives closing and reopening the database', () async {
    await repo.create(article('x', title: 'Vélo'), isOnline: true, explicitId: 'bike');
    await (await repo.database).close();
    final reopened = LocalArticleRepository(
      openDatabase: () => ArticleDatabase.open(factory: databaseFactoryFfi, path: '${dir.path}/articles.db'),
    );
    expect((await reopened.fetchAll(isOnline: false)).single.title, 'Vélo');
    repo = reopened;
  });
}
