import 'package:campusconnect/services/local_photo_store.dart';
import 'package:campusconnect/core/utils/geo.dart';
import 'package:campusconnect/models/article_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/articles.dart';

void main() {
  test('toMap / fromMap round trip keeps every field', () {
    final a = article(
      'a1',
      title: 'Vélo',
      price: 120.5,
      category: 'Autre',
      imageUrls: const ['https://x/1.jpg', 'https://x/2.jpg'],
      status: ArticleStatus.reserved,
      latitude: 36.9,
      longitude: 10.19,
      viewCount: 7,
      favoritedBy: const ['u1'],
    ).copyWith(updatedAt: DateTime(2026, 11, 3));
    final back = ArticleModel.fromMap('a1', a.toMap());
    expect(back.title, 'Vélo');
    expect(back.price, 120.5);
    expect(back.imageUrls, a.imageUrls);
    expect(back.status, ArticleStatus.reserved);
    expect(back.latitude, 36.9);
    expect(back.longitude, 10.19);
    expect(back.viewCount, 7);
    expect(back.favoritedBy, ['u1']);
    expect(back.createdAt, a.createdAt);
    expect(back.updatedAt, DateTime(2026, 11, 3));
  });

  test('fromMap reads cached ISO dates and missing fields', () {
    final a = ArticleModel.fromMap('x', {
      'title': 'Lampe',
      'createdAt': '2026-10-01T10:00:00.000Z',
      'updatedAt': Timestamp.fromDate(DateTime(2026, 10, 2)),
    });
    expect(a.createdAt, DateTime.parse('2026-10-01T10:00:00.000Z'));
    expect(a.updatedAt, DateTime(2026, 10, 2));
    expect(a.category, 'Autre');
    expect(a.isFree, isTrue);
    expect(a.status, ArticleStatus.available);
    expect(a.hasLocation, isFalse);
  });

  test('priceLabel', () {
    expect(article('1', price: null).priceLabel, 'Gratuit');
    expect(article('1', price: 0).priceLabel, 'Gratuit');
    expect(article('1', price: 25).priceLabel, '25 DT');
    expect(article('1', price: 12.5).priceLabel, '12,5 DT');
  });

  test('copyWith can turn a sale into a gift and drop the location', () {
    final a = article('1', price: 30, latitude: 1, longitude: 2);
    final gift = a.copyWith(clearPrice: true, clearLocation: true);
    expect(gift.isFree, isTrue);
    expect(gift.hasLocation, isFalse);
    expect(a.copyWith(title: 'Autre').price, 30);
  });

  test('distanceKmFrom needs both positions', () {
    final a = article('1', latitude: 36.8065, longitude: 10.1815);
    expect(a.distanceKmFrom(null), isNull);
    expect(article('2').distanceKmFrom(const GeoPoint2(36.9, 10.2)), isNull);
    expect(a.distanceKmFrom(const GeoPoint2(36.8992, 10.1897)), closeTo(10.33, 0.05));
  });

  test('isFavoriteOf and coverUrl', () {
    final a = article('1', favoritedBy: const ['u1'], imageUrls: const ['c.jpg', 'd.jpg']);
    expect(a.isFavoriteOf('u1'), isTrue);
    expect(a.isFavoriteOf('u2'), isFalse);
    expect(a.isFavoriteOf(null), isFalse);
    expect(a.coverUrl, 'c.jpg');
    expect(article('2').coverUrl, isNull);
  });

  test('bundled demo photos are neither local nor remote', () {
    expect(isAssetImage('asset:assets/images/demo/lampe_bureau.jpg'), isTrue);
    expect(isLocalImage('asset:assets/images/demo/lampe_bureau.jpg'), isFalse);
    expect(assetPathOf('asset:assets/images/demo/lampe_bureau.jpg'), 'assets/images/demo/lampe_bureau.jpg');
    expect(isLocalImage('/data/photo.jpg'), isTrue);
    expect(isLocalImage('https://x/y.jpg'), isFalse);
  });
}
