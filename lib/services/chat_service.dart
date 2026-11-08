import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/article_model.dart';
import '../models/conversation_model.dart';
import 'local_photo_store.dart';

/// Messagerie Vente & Don : un acheteur écrit au vendeur d'un article.
///
/// - `conversations/{articleId}_{buyerId}` : en-tête (participants, titre et
///   photo de l'article, dernier message, non-lus) ;
/// - `conversations/{id}/messages/{messageId}` : messages, du plus ancien au
///   plus récent.
class ChatService {
  ChatService({FirebaseFirestore? firestore}) : _firestoreOverride = firestore;

  final FirebaseFirestore? _firestoreOverride;
  late final FirebaseFirestore _db = _firestoreOverride ?? FirebaseFirestore.instance;

  static const String collection = 'conversations';

  CollectionReference<Map<String, dynamic>> get _col => _db.collection(collection);

  /// Ouvre (ou crée) la conversation de [buyerId] à propos de [article].
  Future<ConversationModel> openConversation({
    required ArticleModel article,
    required String buyerId,
    required String buyerName,
  }) async {
    if (buyerId == article.ownerId) {
      throw ArgumentError('Le vendeur ne peut pas s\'écrire à lui-même.');
    }
    final id = ConversationModel.idFor(article.id, buyerId);
    final ref = _col.doc(id);
    final snap = await ref.get();
    if (snap.exists) return ConversationModel.fromMap(id, snap.data()!);

    final conversation = ConversationModel(
      id: id,
      articleId: article.id,
      articleTitle: article.title,
      articleImageUrl: _shareableCover(article),
      sellerId: article.ownerId,
      buyerId: buyerId,
      names: {article.ownerId: article.ownerName, buyerId: buyerName},
      participants: [buyerId, article.ownerId],
      updatedAt: DateTime.now(),
    );
    await ref.set(conversation.toMap());
    return conversation;
  }

  /// Photo de couverture si elle est déjà dans Storage (pas un chemin local).
  static String? _shareableCover(ArticleModel article) {
    final cover = article.coverUrl;
    return cover == null || isLocalImage(cover) ? null : cover;
  }

  /// Conversations de [uid], la plus récente d'abord.
  Stream<List<ConversationModel>> watchConversations(String uid) {
    return _col.where('participants', arrayContains: uid).snapshots().map((snap) {
      final list = [for (final d in snap.docs) ConversationModel.fromMap(d.id, d.data())];
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    });
  }

  /// Messages d'une conversation, du plus ancien au plus récent.
  Stream<List<ChatMessage>> watchMessages(String conversationId) {
    return _col
        .doc(conversationId)
        .collection('messages')
        .orderBy('sentAt', descending: true)
        .limit(200)
        .snapshots()
        .map((snap) => [for (final d in snap.docs) ChatMessage.fromMap(d.id, d.data())]
            .reversed
            .toList());
  }

  /// Envoie [text] de la part de [senderId] et marque la conversation non lue
  /// pour l'autre participant.
  Future<void> send(ConversationModel conversation, String senderId, String text) async {
    final body = text.trim();
    if (body.isEmpty) return;
    final clipped = body.length > ChatMessage.maxLength ? body.substring(0, ChatMessage.maxLength) : body;
    final ref = _col.doc(conversation.id);
    final batch = _db.batch();
    batch.set(ref.collection('messages').doc(), {
      'senderId': senderId,
      'text': clipped,
      'sentAt': FieldValue.serverTimestamp(),
    });
    batch.update(ref, {
      'lastMessage': clipped,
      'lastSenderId': senderId,
      'updatedAt': FieldValue.serverTimestamp(),
      'unreadBy': [conversation.otherId(senderId)],
    });
    await batch.commit();
  }

  /// Retire [uid] des non-lus de la conversation.
  Future<void> markRead(String conversationId, String uid) async {
    await _col.doc(conversationId).update({
      'unreadBy': FieldValue.arrayRemove([uid]),
    });
  }
}
