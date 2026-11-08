import 'dart:async';
import 'dart:io';

import 'package:campusconnect/core/utils/article_search.dart';
import 'package:campusconnect/core/utils/geo.dart';
import 'package:campusconnect/models/article_model.dart';
import 'package:campusconnect/providers/article_provider.dart';
import 'package:campusconnect/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/articles.dart';
import '../helpers/mocks.dart';

const _campus = GeoPoint2(36.8992, 10.1897);

void main() {
  late FakeArticleRepo repo;
  late MockStorageService storage;
  late FakePhotoStore photos;
  late List<(String, Map<String, dynamic>)> queuePatches;
  LocationResult location = const LocationResult.found(_campus);

  ArticleProvider make({bool online = true}) => ArticleProvider(
        repository: repo,
        storage: storage,
        locate: () async => location,
        clock: () => DateTime(2026, 11, 6, 15),
        photos: photos,
        patchQueued: (id, patch) async => queuePatches.add((id, patch)),
        networkTimeout: const Duration(milliseconds: 50),
        uploadTimeout: const Duration(milliseconds: 50),
      )..updateConnectivity(online);

  setUpAll(() => registerFallbackValue(<File>[]));

  setUp(() {
    location = const LocationResult.found(_campus);
    storage = MockStorageService();
    photos = FakePhotoStore();
    queuePatches = [];
    repo = FakeArticleRepo([
      article('book', title: 'Livre de Java', category: 'Livres', price: 15, createdAt: DateTime(2026, 11, 1)),
      article('gift', title: 'Manteau', price: null, createdAt: DateTime(2026, 11, 3), favoritedBy: const ['u1']),
      article('sold', title: 'Vélo vendu', status: ArticleStatus.done, createdAt: DateTime(2026, 11, 4)),
      article('mine', ownerId: 'u1', title: 'Ma lampe', price: 200, createdAt: DateTime(2026, 11, 2)),
    ]);
  });

  test('items hide finished articles; all and mine keep them', () async {
    final p = make();
    await p.load();
    expect([for (final a in p.items) a.id], ['gift', 'mine', 'book']);
    expect(p.all.length, 4);
    expect([for (final a in p.mine('seller-1')) a.id], ['sold', 'gift', 'book']);
    expect(p.highestPrice, 200);
  });

  test('legacy filter API still works and notifies', () async {
    final p = make();
    await p.load();
    var notified = 0;
    p.addListener(() => notified++);
    p.setSearch('java');
    expect([for (final a in p.items) a.id], ['book']);
    p.setSearch('');
    p.toggleFreeOnly();
    expect(p.showOnlyFree, isTrue);
    expect([for (final a in p.items) a.id], ['gift']);
    p.toggleFreeOnly();
    p.setCategoryFilter('Livres');
    expect(p.categoryFilter, 'Livres');
    expect([for (final a in p.items) a.id], ['book']);
    p.setCategoryFilter(null);
    expect(p.items.length, 3);
    expect(notified, greaterThanOrEqualTo(6));
  });

  test('setFilters ignores identical filters and resetFilters keeps the query', () async {
    final p = make();
    var notified = 0;
    p.addListener(() => notified++);
    p.setFilters(ArticleFilters.none);
    expect(notified, 0);
    p.setFilters(const ArticleFilters(query: 'x', maxPrice: 10, sort: ArticleSort.popular));
    p.resetFilters();
    expect(p.filters, const ArticleFilters(query: 'x'));
  });

  test('locateUser stores the position or the error message', () async {
    final p = make();
    expect(await p.locateUser(), isTrue);
    expect(p.userPosition, _campus);
    expect(p.locationError, isNull);

    location = const LocationResult.failed(LocationFailure.denied);
    final q = make();
    expect(await q.locateUser(), isFalse);
    expect(q.userPosition, isNull);
    expect(q.locationError, contains('Autorise'));
  });

  test('distanceKmTo uses the user position', () async {
    final p = make();
    final near = article('n', latitude: _campus.latitude, longitude: _campus.longitude);
    expect(p.distanceKmTo(near), isNull);
    await p.locateUser();
    expect(p.distanceKmTo(near), 0);
  });

  test('createArticle uploads photos online then saves their URLs', () async {
    when(() => storage.uploadImages(any(), folder: any(named: 'folder')))
        .thenAnswer((_) async => ['https://cdn/1.jpg', 'https://cdn/2.jpg']);
    final p = make();
    final id = await p.createArticle(
      draft: article('', title: 'Table', ownerId: 'u1'),
      imageFiles: [File('a.jpg'), File('b.jpg')],
    );
    verify(() => storage.uploadImages(any(that: hasLength(2)), folder: 'articles')).called(1);
    expect(repo.creates.single.$1.imageUrls, ['https://cdn/1.jpg', 'https://cdn/2.jpg']);
    expect(repo.creates.single.$2, isTrue);
    expect(p.byId(id)?.title, 'Table');
  });

  test('createArticle offline keeps the photos on the phone and queues the article', () async {
    final p = make(online: false);
    final id = await p.createArticle(draft: article('', title: 'Chaise'), imageFiles: [File('a.jpg'), File('b.jpg')]);
    verifyNever(() => storage.uploadImages(any(), folder: any(named: 'folder')));
    final (item, online) = repo.creates.single;
    expect(online, isFalse);
    expect(item.imageUrls, ['/local/photo-0.jpg', '/local/photo-1.jpg']);
    expect(p.byId(id)!.hasLocalPhotos, isTrue);
    expect(p.pendingPhotoArticles, 1);
  });

  test('a failing upload while "online" falls back to local photos', () async {
    when(() => storage.uploadImages(any(), folder: any(named: 'folder')))
        .thenThrow(Exception('Unable to resolve host'));
    final p = make();
    await p.createArticle(draft: article('', title: 'Lampe'), imageFiles: [File('a.jpg')]);
    expect(repo.creates.single.$1.imageUrls, ['/local/photo-0.jpg']);
  });

  test('a write that never reaches Firebase is queued after the timeout', () async {
    repo.hangOnline = true;
    when(() => storage.uploadImages(any(), folder: any(named: 'folder')))
        .thenAnswer((_) => Completer<List<String>>().future);
    final p = make();
    final id = await p.createArticle(draft: article('', title: 'Veste'), imageFiles: [File('v.jpg')]);
    final (item, online) = repo.creates.single;
    expect(online, isFalse);
    expect(item.imageUrls, ['/local/photo-0.jpg']);
    expect(p.byId(id), isNotNull);
  });

  test('syncPendingPhotos uploads, replaces the paths everywhere and cleans up', () async {
    final p = make(online: false);
    final id = await p.createArticle(
      draft: article('', title: 'Livre'),
      imageFiles: [File('a.jpg'), File('b.jpg')],
    );
    expect(await p.syncPendingPhotos(), 0); // toujours hors ligne

    when(() => storage.uploadImages(any(), folder: any(named: 'folder')))
        .thenAnswer((_) async => ['https://cdn/a.jpg', 'https://cdn/b.jpg']);
    p.updateConnectivity(true); // déclenche la synchro
    await pumpEventQueue();

    expect(p.byId(id)!.imageUrls, ['https://cdn/a.jpg', 'https://cdn/b.jpg']);
    expect(p.byId(id)!.hasLocalPhotos, isFalse);
    expect(repo.updates.last.$2, {'imageUrls': ['https://cdn/a.jpg', 'https://cdn/b.jpg']});
    expect(queuePatches.single.$1, id);
    expect(photos.files, isEmpty);
    expect(photos.discarded, hasLength(2));
    expect(p.pendingPhotoArticles, 0);
  });

  test('syncPendingPhotos keeps the photos when the upload still fails', () async {
    final p = make(online: false);
    final id = await p.createArticle(draft: article('', title: 'Livre'), imageFiles: [File('a.jpg')]);
    when(() => storage.uploadImages(any(), folder: any(named: 'folder')))
        .thenThrow(Exception('offline'));
    p.updateConnectivity(true);
    expect(await p.syncPendingPhotos(), 0);
    expect(p.byId(id)!.imageUrls, ['/local/photo-0.jpg']);
    expect(photos.files, hasLength(1));
  });

  test('photo paths from another phone are dropped, not uploaded', () async {
    repo = FakeArticleRepo([
      article('x', imageUrls: const ['https://cdn/ok.jpg', '/autre/telephone.jpg']),
    ]);
    final p = make();
    await p.load();
    expect(p.pendingPhotoArticles, 0);
    expect(await p.syncPendingPhotos(), 0);
    verifyNever(() => storage.uploadImages(any(), folder: any(named: 'folder')));
  });

  test('createArticle keeps at most 6 photos', () async {
    when(() => storage.uploadImages(any(), folder: any(named: 'folder'))).thenAnswer((_) async => []);
    final p = make();
    await p.createArticle(
      draft: article(''),
      imageFiles: List.generate(9, (i) => File('$i.jpg')),
    );
    verify(() => storage.uploadImages(any(that: hasLength(6)), folder: 'articles')).called(1);
  });

  test('editArticle sends a patch with kept + new photos and the location', () async {
    when(() => storage.uploadImages(any(), folder: any(named: 'folder')))
        .thenAnswer((_) async => ['https://cdn/new.jpg']);
    final p = make();
    await p.load();
    final original = p.byId('book')!;
    await p.editArticle(
      original,
      title: 'Livre de Java (2e éd.)',
      description: 'Annoté',
      category: 'Livres',
      price: 12,
      keptUrls: const ['https://cdn/old.jpg'],
      newImages: [File('n.jpg')],
      location: _campus,
    );
    final (id, patch, online) = repo.updates.single;
    expect(id, 'book');
    expect(online, isTrue);
    expect(patch['title'], 'Livre de Java (2e éd.)');
    expect(patch['price'], 12);
    expect(patch['imageUrls'], ['https://cdn/old.jpg', 'https://cdn/new.jpg']);
    expect(patch['latitude'], _campus.latitude);
    expect(patch['updatedAt'], DateTime(2026, 11, 6, 15));
    expect(p.byId('book')!.title, 'Livre de Java (2e éd.)');
  });

  test('editArticle can make a gift and remove the location', () async {
    final p = make();
    await p.load();
    await p.editArticle(p.byId('book')!,
        title: 'Livre', description: 'Donné', category: 'Livres', price: null,
        keptUrls: const [], removeLocation: true);
    final patch = repo.updates.single.$2;
    expect(patch.containsKey('price'), isTrue);
    expect(patch['price'], isNull);
    expect(patch.containsKey('latitude'), isTrue);
    expect(patch['latitude'], isNull);
    expect(p.byId('book')!.isFree, isTrue);
  });

  test('editArticle offline keeps the new photos locally', () async {
    final p = make(online: false);
    await p.load();
    await p.editArticle(p.byId('book')!,
        title: 'Livre', description: 'Avec photo', category: 'Livres', price: 1,
        keptUrls: const ['https://cdn/old.jpg'], newImages: [File('x.jpg')]);
    final patch = repo.updates.single.$2;
    expect(patch['imageUrls'], ['https://cdn/old.jpg', '/local/photo-0.jpg']);
    expect(repo.updates.single.$3, isFalse);
  });

  test('status changes and delete', () async {
    final p = make();
    await p.load();
    await p.markAsReserved('book');
    expect(p.byId('book')!.status, ArticleStatus.reserved);
    await p.markAsAvailable('book');
    expect(p.byId('book')!.status, ArticleStatus.available);
    await p.markAsDone('book');
    expect(p.items.any((a) => a.id == 'book'), isFalse);
    await p.deleteArticle('book');
    expect(p.byId('book'), isNull);
    expect(repo.deletes.single.$1, 'book');
  });

  test('toggleFavorite adds then removes only this user', () async {
    final p = make();
    await p.load();
    await p.toggleFavorite('gift', 'u2');
    expect(p.byId('gift')!.favoritedBy, ['u1', 'u2']);
    expect(repo.updates.last.$2, {'favoritedBy': ['u1', 'u2']});
    await p.toggleFavorite('gift', 'u2');
    expect(p.byId('gift')!.favoritedBy, ['u1']);
    expect(p.favoritesOf('u1').map((a) => a.id), ['gift']);
  });

  test('recordView counts once per session, never for the owner or a visitor', () async {
    final p = make();
    await p.load();
    await p.recordView('book', 'u2');
    await p.recordView('book', 'u2');
    await p.recordView('book', 'seller-1'); // propriétaire
    await p.recordView('book', null); // visiteur
    expect(p.byId('book')!.viewCount, 1);
    expect(repo.updates.where((u) => u.$1 == 'book').single.$2, {'viewCount': 1});
  });

  test('photo search ranks lookalikes and can be cleared', () async {
    repo = FakeArticleRepo([
      article('b1', title: 'Livre', labels: const ['book', 'paper']),
      article('b2', title: 'Cahier', labels: const ['paper']),
      article('l', title: 'Lampe', labels: const ['lamp']),
    ]);
    final p = make();
    await p.load();
    p.setPhotoSearch(['Book', 'Paper']);
    expect(p.isPhotoSearch, isTrue);
    expect([for (final a in p.items) a.id], ['b1', 'b2']);
    p.clearPhotoSearch();
    expect(p.items.length, 3);
  });

  test('recommendations and price advice come from the loaded articles', () async {
    repo = FakeArticleRepo([
      article('fav', title: 'Livre Java', category: 'Livres', price: 20, favoritedBy: const ['u9']),
      article('py', title: 'Livre Python', category: 'Livres', price: 30),
    ]);
    final p = make();
    await p.load();
    expect([for (final a in p.recommendationsFor('u9')) a.id], ['py']);
    final advice = p.priceAdviceFor(title: 'Livre C++', category: 'Livres')!;
    expect(advice.basedOn, 2);
    expect(advice.suggested, 25);
  });

  test('editArticle saves new photo labels', () async {
    final p = make();
    await p.load();
    await p.editArticle(p.byId('book')!,
        title: 'Livre', description: 'd', category: 'Livres', price: 1, keptUrls: const [], labels: const ['book']);
    expect(repo.updates.single.$2['labels'], ['book']);
    expect(p.byId('book')!.labels, ['book']);
  });

  test('addDemoArticles adds the 4 demo articles with bundled photos, once', () async {
    final p = make();
    await p.load();
    final added = await p.addDemoArticles(ownerId: 'u1', ownerName: 'Ranim');
    expect(added, 4);
    final demos = [for (final (a, _) in repo.creates) a];
    expect(demos.map((a) => a.title), [
      'Livre d\'algorithmique',
      'Lampe de bureau LED',
      'Calculatrice scientifique',
      'Veste d\'hiver',
    ]);
    expect(demos.every((a) => a.ownerId == 'u1' && a.ownerName == 'Ranim'), isTrue);
    expect(demos.first.imageUrls.single, 'asset:assets/images/demo/livre_algo.jpg');
    expect(demos.last.price, isNull);
    expect(demos.every((a) => !a.hasLocalPhotos && a.hasLocation && a.labels.isNotEmpty), isTrue);
    verifyNever(() => storage.uploadImages(any(), folder: any(named: 'folder')));

    // Un 2e appui n'ajoute rien.
    expect(await p.addDemoArticles(ownerId: 'u1', ownerName: 'Ranim'), 0);
    expect(repo.creates, hasLength(4));
  });
}
