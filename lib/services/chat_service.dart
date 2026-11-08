import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/article_model.dart';
import '../models/conversation_model.dart';
import 'sqlite/article_database.dart';

/// Messagerie Vente & Don, **dans la base SQLite du téléphone** : un acheteur
/// écrit au vendeur d'un article.
///
/// - table `conversations` : une ligne par couple article + acheteur (id
///   `{articleId}_{buyerId}`), avec le dernier message et les non-lus ;
/// - table `messages` : les messages, du plus ancien au plus récent.
///
/// Les écrans écoutent [watchConversations] et [watchMessages] : chaque envoi
/// ou lecture les met à jour tout de suite.
class ChatService {
  ChatService({Future<ArticleDatabase> Function()? openDatabase, DateTime Function()? clock})
      : _openDatabase = openDatabase ?? ArticleDatabase.open,
        _clock = clock ?? DateTime.now;

  final Future<ArticleDatabase> Function() _openDatabase;
  final DateTime Function() _clock;
  late final Future<Database> _db = _openDatabase().then((d) => d.db);

  /// Signale un changement à tous les écrans ouverts (toutes instances).
  static final StreamController<void> _changes = StreamController<void>.broadcast();

  static const _conv = ArticleDatabase.conversationsTable;
  static const _msg = ArticleDatabase.messagesTable;

  /// Ouvre (ou crée) la conversation de [buyerId] à propos de [article].
  Future<ConversationModel> openConversation({
    required ArticleModel article,
    required String buyerId,
    required String buyerName,
  }) async {
    if (buyerId == article.ownerId) {
      throw ArgumentError('Le vendeur ne peut pas s\'écrire à lui-même.');
    }
    final db = await _db;
    final id = ConversationModel.idFor(article.id, buyerId);
    final existing = await db.query(_conv, where: 'id = ?', whereArgs: [id], limit: 1);
    if (existing.isNotEmpty) return _fromRow(existing.first);

    await db.insert(_conv, {
      'id': id,
      'article_id': article.id,
      'article_title': article.title,
      'article_image_url': article.coverUrl,
      'seller_id': article.ownerId,
      'seller_name': article.ownerName,
      'buyer_id': buyerId,
      'buyer_name': buyerName,
      'updated_at': _clock().millisecondsSinceEpoch,
    });
    _changes.add(null);
    final created = await db.query(_conv, where: 'id = ?', whereArgs: [id], limit: 1);
    return _fromRow(created.first);
  }

  /// Conversations de [uid], la plus récente d'abord.
  Stream<List<ConversationModel>> watchConversations(String uid) =>
      _watch(() => _conversationsOf(uid));

  /// Messages d'une conversation, du plus ancien au plus récent (200 derniers).
  Stream<List<ChatMessage>> watchMessages(String conversationId) =>
      _watch(() => _messagesOf(conversationId));

  /// Envoie [text] de la part de [senderId] et marque la conversation non lue
  /// pour l'autre participant.
  Future<void> send(ConversationModel conversation, String senderId, String text) async {
    final body = text.trim();
    if (body.isEmpty) return;
    final clipped = body.length > ChatMessage.maxLength ? body.substring(0, ChatMessage.maxLength) : body;
    final now = _clock().millisecondsSinceEpoch;
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert(_msg, {
        'conversation_id': conversation.id,
        'sender_id': senderId,
        'text': clipped,
        'sent_at': now,
      });
      await txn.update(
        _conv,
        {
          'last_message': clipped,
          'last_sender_id': senderId,
          'updated_at': now,
          'unread_by': jsonEncode([conversation.otherId(senderId)]),
        },
        where: 'id = ?',
        whereArgs: [conversation.id],
      );
    });
    _changes.add(null);
  }

  /// Retire [uid] des non-lus de la conversation.
  Future<void> markRead(String conversationId, String uid) async {
    final db = await _db;
    final rows = await db.query(_conv, columns: ['unread_by'], where: 'id = ?', whereArgs: [conversationId]);
    if (rows.isEmpty) return;
    final unread = List<String>.from(jsonDecode(rows.first['unread_by'] as String) as List);
    if (!unread.remove(uid)) return;
    await db.update(_conv, {'unread_by': jsonEncode(unread)}, where: 'id = ?', whereArgs: [conversationId]);
    _changes.add(null);
  }

  // ---------------------------------------------------------------- interne

  /// Émet le résultat de [read] tout de suite puis après chaque changement.
  /// L'abonnement aux changements s'arrête dès que l'écran ne l'écoute plus.
  Stream<T> _watch<T>(Future<T> Function() read) {
    late final StreamController<T> controller;
    StreamSubscription<void>? changes;
    Future<void> emit() async {
      try {
        final value = await read();
        if (!controller.isClosed) controller.add(value);
      } catch (e, s) {
        if (!controller.isClosed) controller.addError(e, s);
      }
    }

    controller = StreamController<T>(
      onListen: () {
        emit();
        changes = _changes.stream.listen((_) => emit());
      },
      onCancel: () async {
        await changes?.cancel();
        await controller.close();
      },
    );
    return controller.stream;
  }

  Future<List<ConversationModel>> _conversationsOf(String uid) async {
    final db = await _db;
    final rows = await db.query(_conv,
        where: 'seller_id = ? OR buyer_id = ?', whereArgs: [uid, uid], orderBy: 'updated_at DESC');
    return [for (final r in rows) _fromRow(r)];
  }

  Future<List<ChatMessage>> _messagesOf(String conversationId) async {
    final db = await _db;
    final rows = await db.query(_msg,
        where: 'conversation_id = ?', whereArgs: [conversationId], orderBy: 'sent_at DESC, id DESC', limit: 200);
    return [
      for (final r in rows.reversed)
        ChatMessage(
          id: '${r['id']}',
          senderId: r['sender_id'] as String,
          text: r['text'] as String,
          sentAt: DateTime.fromMillisecondsSinceEpoch(r['sent_at'] as int),
        ),
    ];
  }

  static ConversationModel _fromRow(Map<String, Object?> r) {
    final seller = r['seller_id'] as String;
    final buyer = r['buyer_id'] as String;
    return ConversationModel(
      id: r['id'] as String,
      articleId: r['article_id'] as String,
      articleTitle: r['article_title'] as String,
      articleImageUrl: r['article_image_url'] as String?,
      sellerId: seller,
      buyerId: buyer,
      names: {seller: r['seller_name'] as String, buyer: r['buyer_name'] as String},
      participants: [buyer, seller],
      lastMessage: r['last_message'] as String? ?? '',
      lastSenderId: r['last_sender_id'] as String?,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
      unreadBy: List<String>.from(jsonDecode(r['unread_by'] as String? ?? '[]') as List),
    );
  }
}
