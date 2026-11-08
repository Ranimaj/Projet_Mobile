import 'dart:io';

import 'package:campusconnect/services/chat_service.dart';
import 'package:campusconnect/services/sqlite/article_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../helpers/articles.dart';

void main() {
  late Directory dir;
  late ArticleDatabase db;
  late ChatService chat;
  var now = DateTime(2026, 11, 8, 10);
  final item = article('a1', ownerId: 'alice', ownerName: 'Amel Ben Salah', title: 'TI-83',
      imageUrls: const ['asset:assets/images/demo/calculatrice.jpg']);

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vente_don_chat');
    db = await ArticleDatabase.open(factory: databaseFactoryFfi, path: '${dir.path}/chat.db');
    now = DateTime(2026, 11, 8, 10);
    chat = ChatService(openDatabase: () async => db, clock: () => now);
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  test('openConversation creates the row once, then reuses it', () async {
    final c = await chat.openConversation(article: item, buyerId: 'bob', buyerName: 'Bob');
    expect(c.id, 'a1_bob');
    expect(c.sellerId, 'alice');
    expect(c.participants, containsAll(['alice', 'bob']));
    expect(c.otherName('bob'), 'Amel Ben Salah');
    expect(c.otherName('alice'), 'Bob');
    expect(c.articleImageUrl, 'asset:assets/images/demo/calculatrice.jpg');

    await chat.openConversation(article: item, buyerId: 'bob', buyerName: 'Bob');
    expect(await db.db.query(ArticleDatabase.conversationsTable), hasLength(1));
  });

  test('the seller cannot open a conversation with themselves', () {
    expect(
      () => chat.openConversation(article: item, buyerId: 'alice', buyerName: 'Amel'),
      throwsArgumentError,
    );
  });

  test('send stores the message, updates the header and marks it unread for the other', () async {
    final c = await chat.openConversation(article: item, buyerId: 'bob', buyerName: 'Bob');
    await chat.send(c, 'bob', '  Toujours dispo ?  ');
    now = now.add(const Duration(minutes: 1));
    await chat.send(c, 'alice', 'Oui !');

    final messages = await chat.watchMessages(c.id).first;
    expect([for (final m in messages) m.text], ['Toujours dispo ?', 'Oui !']);
    expect(messages.first.senderId, 'bob');

    final forBob = await chat.watchConversations('bob').first;
    expect(forBob.single.lastMessage, 'Oui !');
    expect(forBob.single.isUnreadFor('bob'), isTrue);
    expect(forBob.single.isUnreadFor('alice'), isFalse);

    await chat.markRead(c.id, 'bob');
    expect((await chat.watchConversations('bob').first).single.isUnreadFor('bob'), isFalse);
  });

  test('empty messages are ignored and long ones are clipped', () async {
    final c = await chat.openConversation(article: item, buyerId: 'bob', buyerName: 'Bob');
    await chat.send(c, 'bob', '   ');
    await chat.send(c, 'bob', 'x' * 1500);
    final messages = await chat.watchMessages(c.id).first;
    expect(messages.single.text.length, 1000);
  });

  test('the streams emit again after a new message', () async {
    final c = await chat.openConversation(article: item, buyerId: 'bob', buyerName: 'Bob');
    final seen = <int>[];
    final sub = chat.watchMessages(c.id).listen((m) => seen.add(m.length));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await chat.send(c, 'bob', 'Bonjour');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await sub.cancel();
    expect(seen, [0, 1]);
  });

  test('conversations are listed for both participants, most recent first', () async {
    final other = article('a2', ownerId: 'alice', ownerName: 'Amel', title: 'Lampe');
    final c1 = await chat.openConversation(article: item, buyerId: 'bob', buyerName: 'Bob');
    now = now.add(const Duration(minutes: 5));
    await chat.openConversation(article: other, buyerId: 'bob', buyerName: 'Bob');
    now = now.add(const Duration(minutes: 5));
    await chat.send(c1, 'bob', 'Je passe ce soir');

    final forAlice = await chat.watchConversations('alice').first;
    expect([for (final c in forAlice) c.articleTitle], ['TI-83', 'Lampe']);
    expect(await chat.watchConversations('carl').first, isEmpty);
  });
}
