import 'package:campusconnect/models/conversation_model.dart';
import 'package:campusconnect/services/chat_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/articles.dart';

void main() {
  late FakeFirebaseFirestore db;
  late ChatService chat;
  final item = article('a1', ownerId: 'alice', ownerName: 'Amel Ben Salah', title: 'TI-83',
      imageUrls: const ['https://cdn/ti83.jpg']);

  setUp(() {
    db = FakeFirebaseFirestore();
    chat = ChatService(firestore: db);
  });

  test('openConversation creates the header once, then reuses it', () async {
    final c = await chat.openConversation(article: item, buyerId: 'bob', buyerName: 'Bob');
    expect(c.id, 'a1_bob');
    expect(c.sellerId, 'alice');
    expect(c.participants, containsAll(['alice', 'bob']));
    expect(c.otherName('bob'), 'Amel Ben Salah');
    expect(c.otherName('alice'), 'Bob');

    final stored = await db.collection('conversations').doc('a1_bob').get();
    expect(stored.data()!['articleTitle'], 'TI-83');
    expect(stored.data()!['articleImageUrl'], 'https://cdn/ti83.jpg');

    await db.collection('conversations').doc('a1_bob').update({'lastMessage': 'Salut'});
    final again = await chat.openConversation(article: item, buyerId: 'bob', buyerName: 'Bob');
    expect(again.lastMessage, 'Salut');
    expect((await db.collection('conversations').get()).docs.length, 1);
  });

  test('the seller cannot open a conversation with themselves', () async {
    expect(
      () => chat.openConversation(article: item, buyerId: 'alice', buyerName: 'Amel'),
      throwsArgumentError,
    );
  });

  test('send stores the message and marks it unread for the other side', () async {
    final c = await chat.openConversation(article: item, buyerId: 'bob', buyerName: 'Bob');
    await chat.send(c, 'bob', '  Toujours disponible ?  ');
    await chat.send(c, 'bob', '   ');

    final messages = await chat.watchMessages(c.id).first;
    expect(messages.map((m) => m.text), ['Toujours disponible ?']);
    expect(messages.single.senderId, 'bob');

    final header = ConversationModel.fromMap(
        c.id, (await db.collection('conversations').doc(c.id).get()).data()!);
    expect(header.lastMessage, 'Toujours disponible ?');
    expect(header.lastSenderId, 'bob');
    expect(header.isUnreadFor('alice'), isTrue);
    expect(header.isUnreadFor('bob'), isFalse);

    await chat.markRead(c.id, 'alice');
    final read = (await db.collection('conversations').doc(c.id).get()).data()!;
    expect(read['unreadBy'], isEmpty);
  });

  test('messages come back oldest first', () async {
    final c = await chat.openConversation(article: item, buyerId: 'bob', buyerName: 'Bob');
    final msgs = db.collection('conversations').doc(c.id).collection('messages');
    await msgs.add({'senderId': 'bob', 'text': 'Un', 'sentAt': DateTime(2026, 11, 5, 10)});
    await msgs.add({'senderId': 'alice', 'text': 'Deux', 'sentAt': DateTime(2026, 11, 5, 11)});
    await msgs.add({'senderId': 'bob', 'text': 'Trois', 'sentAt': DateTime(2026, 11, 5, 12)});
    final list = await chat.watchMessages(c.id).first;
    expect(list.map((m) => m.text), ['Un', 'Deux', 'Trois']);
  });

  test('long messages are cut to the maximum length', () async {
    final c = await chat.openConversation(article: item, buyerId: 'bob', buyerName: 'Bob');
    await chat.send(c, 'bob', 'x' * 1500);
    final list = await chat.watchMessages(c.id).first;
    expect(list.single.text.length, ChatMessage.maxLength);
  });

  test('watchConversations lists only mine, most recent first', () async {
    final other = article('a2', ownerId: 'carol', ownerName: 'Carol', title: 'Lampe');
    final c1 = await chat.openConversation(article: item, buyerId: 'bob', buyerName: 'Bob');
    await chat.openConversation(article: other, buyerId: 'dan', buyerName: 'Dan');
    final c3 = await chat.openConversation(article: other, buyerId: 'bob', buyerName: 'Bob');
    await db.collection('conversations').doc(c1.id).update({'updatedAt': DateTime(2026, 11, 1)});
    await db.collection('conversations').doc(c3.id).update({'updatedAt': DateTime(2026, 11, 4)});

    final bobs = await chat.watchConversations('bob').first;
    expect(bobs.map((c) => c.id), ['a2_bob', 'a1_bob']);
    final alices = await chat.watchConversations('alice').first;
    expect(alices.map((c) => c.id), ['a1_bob']);
  });
}
