import 'dart:async';

import 'package:campusconnect/models/article_model.dart';
import 'package:campusconnect/models/conversation_model.dart';
import 'package:campusconnect/services/chat_service.dart';

/// Messagerie en mémoire pour les tests d'écrans (la vraie utilise SQLite,
/// testée dans test/services/chat_service_test.dart).
class FakeChatService extends ChatService {
  final Map<String, ConversationModel> conversations = {};
  final Map<String, List<ChatMessage>> messages = {};
  final StreamController<void> _changed = StreamController<void>.broadcast();

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    await for (final _ in _changed.stream) {
      yield read();
    }
  }

  @override
  Future<ConversationModel> openConversation({
    required ArticleModel article,
    required String buyerId,
    required String buyerName,
  }) async {
    if (buyerId == article.ownerId) throw ArgumentError('même personne');
    final id = ConversationModel.idFor(article.id, buyerId);
    return conversations[id] ??= ConversationModel(
      id: id,
      articleId: article.id,
      articleTitle: article.title,
      articleImageUrl: article.coverUrl,
      sellerId: article.ownerId,
      buyerId: buyerId,
      names: {article.ownerId: article.ownerName, buyerId: buyerName},
      participants: [buyerId, article.ownerId],
      updatedAt: DateTime(2026, 11, 8),
    );
  }

  @override
  Stream<List<ConversationModel>> watchConversations(String uid) =>
      _watch(() => [for (final c in conversations.values) if (c.participants.contains(uid)) c]);

  @override
  Stream<List<ChatMessage>> watchMessages(String conversationId) =>
      _watch(() => List.of(messages[conversationId] ?? const []));

  @override
  Future<void> send(ConversationModel conversation, String senderId, String text) async {
    final list = messages.putIfAbsent(conversation.id, () => []);
    list.add(ChatMessage(id: '${list.length}', senderId: senderId, text: text.trim(), sentAt: DateTime(2026, 11, 8)));
    final c = conversations[conversation.id] ?? conversation;
    conversations[conversation.id] = ConversationModel(
      id: c.id,
      articleId: c.articleId,
      articleTitle: c.articleTitle,
      articleImageUrl: c.articleImageUrl,
      sellerId: c.sellerId,
      buyerId: c.buyerId,
      names: c.names,
      participants: c.participants,
      lastMessage: text.trim(),
      lastSenderId: senderId,
      updatedAt: c.updatedAt,
      unreadBy: [c.otherId(senderId)],
    );
    _changed.add(null);
  }

  @override
  Future<void> markRead(String conversationId, String uid) async {}
}
