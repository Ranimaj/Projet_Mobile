import 'dart:io';

import 'package:campusconnect/core/utils/offline_queue_service.dart';
import 'package:campusconnect/models/article_model.dart';
import 'package:campusconnect/services/sqlite/article_database.dart';
import 'package:campusconnect/services/sqlite/sqlite_article_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/articles.dart';

/// File d'attente en mémoire (la vraie utilise Hive).
class _MemoryQueue extends OfflineQueueService {
  final List<QueuedAction> actions = [];

  @override
  List<QueuedAction> get pendingActions => List.unmodifiable(actions);

  @override
  String enqueue({
    required QueueActionType type,
    required String collection,
    required Map<String, dynamic> payload,
    String? docId,
  }) {
    final id = 'q${actions.length}';
    actions.add(QueuedAction(
      id: id,
      type: type,
      collection: collection,
      docId: docId ?? '',
      payload: payload,
      queuedAt: DateTime(2026, 11, 8),
    ));
    return id;
  }
}

void main() {
  late Directory dir;
  late FakeFirebaseFirestore firestore;
  late _MemoryQueue queue;
  late SqliteArticleRepository repo;
  var n = 0;

  setUpAll(sqfliteFfiInit);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('vente_don_sqlite');
    firestore = FakeFirebaseFirestore();
    queue = _MemoryQueue();
    final path = '${dir.path}/articles_${n++}.db';
    repo = SqliteArticleRepository(
      openDatabase: () => ArticleDatabase.open(factory: databaseFactoryFfi, path: path),
      firestore: firestore,
      queue: queue,
    );
  });

  tearDown(() async {
    await (await repo.database).close();
    dir.deleteSync(recursive: true);
  });

  test('a row keeps every field of the article', () async {
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
    final back = ArticleDatabase.fromRow(ArticleDatabase.toRow(a, SyncState.synced));
    expect(back.toMap(), a.toMap());
  });

  test('online, a new article is saved in SQLite and sent to Firebase', () async {
    final id = await repo.create(article('x', title: 'Lampe'), isOnline: true, explicitId: 'lamp');
    expect(id, 'lamp');
    expect((await firestore.collection('articles').doc('lamp').get()).data()!['title'], 'Lampe');
    final db = await repo.database;
    expect(await db.syncStateOf('lamp'), SyncState.synced);
    expect(queue.actions, isEmpty);
  });

  test('offline, the article stays in SQLite as pending and is queued', () async {
    await repo.create(article('x', title: 'Livre'), isOnline: false, explicitId: 'book');
    expect((await firestore.collection('articles').doc('book').get()).exists, isFalse);
    expect(queue.actions.single.type, QueueActionType.create);
    final db = await repo.database;
    expect(await db.syncStateOf('book'), SyncState.pending);
    expect((await repo.fetchAll(isOnline: false)).map((a) => a.title), ['Livre']);
  });

  test('online reading brings the other students\' articles into SQLite', () async {
    await firestore.collection('articles').doc('other').set(article('other', title: 'Vélo').toMap());
    final items = await repo.fetchAll(isOnline: true);
    expect(items.map((a) => a.id), ['other']);
    // Hors ligne ensuite : toujours là, lu depuis SQLite.
    expect((await repo.fetchAll(isOnline: false)).map((a) => a.title), ['Vélo']);
  });

  test('an unsent local change is not overwritten by Firebase', () async {
    await firestore.collection('articles').doc('a').set(article('a', title: 'Ancien titre').toMap());
    await repo.fetchAll(isOnline: true);
    await repo.update('a', {'title': 'Nouveau titre', 'status': 'reserved'}, isOnline: false);

    var items = await repo.fetchAll(isOnline: true);
    expect(items.single.title, 'Nouveau titre');
    expect(items.single.status, ArticleStatus.reserved);

    // Une fois la file vidée (synchro faite), Firebase fait foi.
    queue.actions.clear();
    await firestore.collection('articles').doc('a').update({'title': 'Nouveau titre', 'status': 'reserved'});
    items = await repo.fetchAll(isOnline: true);
    expect(items.single.title, 'Nouveau titre');
    expect(await (await repo.database).syncStateOf('a'), SyncState.synced);
  });

  test('an offline delete hides the article until it is synced', () async {
    await firestore.collection('articles').doc('a').set(article('a', title: 'Calculatrice').toMap());
    await repo.fetchAll(isOnline: true);
    await repo.delete('a', isOnline: false);

    expect(await repo.fetchAll(isOnline: false), isEmpty);
    // Firebase a encore l'article, mais la suppression attend dans la file.
    expect(await repo.fetchAll(isOnline: true), isEmpty);
    expect(queue.actions.single.type, QueueActionType.delete);

    queue.actions.clear();
    await firestore.collection('articles').doc('a').delete();
    expect(await repo.fetchAll(isOnline: true), isEmpty);
    expect(await (await repo.database).syncStateOf('a'), isNull);
  });

  test('online update and delete reach Firebase and SQLite', () async {
    await repo.create(article('x', title: 'Chaise'), isOnline: true, explicitId: 'c');
    await repo.update('c', {'favoritedBy': ['u1']}, isOnline: true);
    expect((await firestore.collection('articles').doc('c').get()).data()!['favoritedBy'], ['u1']);
    expect((await repo.fetchAll(isOnline: false)).single.favoritedBy, ['u1']);

    await repo.delete('c', isOnline: true);
    expect((await firestore.collection('articles').doc('c').get()).exists, isFalse);
    expect(await repo.fetchAll(isOnline: false), isEmpty);
  });
}
