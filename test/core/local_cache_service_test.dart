import 'dart:io';

import 'package:campusconnect/core/utils/local_cache_service.dart';
import 'package:campusconnect/models/article_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory dir;
  final service = LocalCacheService();

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('cache_test');
    Hive.init(dir.path);
    await Hive.openBox('test_box');
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
    await dir.delete(recursive: true);
  });

  test('sanitize converts Firestore types into Hive-storable primitives, recursively', () {
    final out = LocalCacheService.sanitize({
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 10, 15, 9)),
      'where': const GeoPoint(36.8, 10.2),
      'tags': ['a', Timestamp.fromDate(DateTime.utc(2026, 1, 1))],
      'nested': {'deadline': null, 'n': 3},
    }) as Map<String, dynamic>;

    expect(out['createdAt'], '2026-10-15T09:00:00.000Z');
    expect(out['where'], {'latitude': 36.8, 'longitude': 10.2});
    expect(out['tags'], ['a', '2026-01-01T00:00:00.000Z']);
    expect(out['nested'], {'deadline': null, 'n': 3});
  });

  test('a collection with Timestamps is cached and read back as model-parsable maps', () async {
    // Avant le correctif, Hive levait "Cannot write, unknown type: Timestamp"
    // et le repository renvoyait silencieusement une liste vide.
    await service.cacheCollection('test_box', {
      'a1': {
        'ownerId': 'u',
        'ownerName': 'Amel',
        'title': 'Calculatrice',
        'description': '',
        'price': 120.0,
        'category': 'Fournitures',
        'imageUrls': <String>[],
        'status': 'available',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 10, 15, 9)),
        'viewCount': 1,
        'favoritedBy': <String>[],
      },
    });

    final cached = service.readCollection('test_box');
    expect(cached.keys, ['a1']);
    final article = ArticleModel.fromMap('a1', cached['a1']!);
    expect(article.title, 'Calculatrice');
    expect(article.createdAt.toUtc(), DateTime.utc(2026, 10, 15, 9));
    expect(article.price, 120);
  });

  test('upsert and remove keep the cache consistent', () async {
    await service.upsert('test_box', 'b1', {'title': 'x', 'at': Timestamp.fromDate(DateTime.utc(2026))});
    expect(service.readCollection('test_box')['b1']!['at'], '2026-01-01T00:00:00.000Z');
    await service.removeFromCache('test_box', 'b1');
    expect(service.readCollection('test_box').containsKey('b1'), isFalse);
  });
}
