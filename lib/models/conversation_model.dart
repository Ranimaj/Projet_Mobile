
DateTime? _date(dynamic v) {
  if (v is DateTime) return v;
  if (v == null) return null;
  return DateTime.tryParse(v.toString());
}

/// Conversation entre un acheteur et le vendeur d'un article (Vente & Don).
/// Document `conversations/{articleId}_{buyerId}`.
class ConversationModel {
  final String id;
  final String articleId;
  final String articleTitle;
  final String? articleImageUrl;
  final String sellerId;
  final String buyerId;
  final Map<String, String> names; // uid -> nom affiché
  final List<String> participants;
  final String lastMessage;
  final String? lastSenderId;
  final DateTime updatedAt;

  /// Participants qui n'ont pas encore lu le dernier message.
  final List<String> unreadBy;

  const ConversationModel({
    required this.id,
    required this.articleId,
    required this.articleTitle,
    this.articleImageUrl,
    required this.sellerId,
    required this.buyerId,
    required this.names,
    required this.participants,
    this.lastMessage = '',
    this.lastSenderId,
    required this.updatedAt,
    this.unreadBy = const [],
  });

  static String idFor(String articleId, String buyerId) => '${articleId}_$buyerId';

  /// Uid de l'autre participant, vu par [me].
  String otherId(String me) => me == sellerId ? buyerId : sellerId;

  String otherName(String me) => names[otherId(me)] ?? 'Utilisateur';

  bool isUnreadFor(String me) => unreadBy.contains(me);

  factory ConversationModel.fromMap(String id, Map<String, dynamic> map) {
    return ConversationModel(
      id: id,
      articleId: map['articleId'] ?? '',
      articleTitle: map['articleTitle'] ?? '',
      articleImageUrl: map['articleImageUrl'],
      sellerId: map['sellerId'] ?? '',
      buyerId: map['buyerId'] ?? '',
      names: Map<String, String>.from(map['names'] ?? const {}),
      participants: List<String>.from(map['participants'] ?? const []),
      lastMessage: map['lastMessage'] ?? '',
      lastSenderId: map['lastSenderId'],
      updatedAt: _date(map['updatedAt']) ?? DateTime.now(),
      unreadBy: List<String>.from(map['unreadBy'] ?? const []),
    );
  }

  Map<String, dynamic> toMap() => {
        'articleId': articleId,
        'articleTitle': articleTitle,
        'articleImageUrl': articleImageUrl,
        'sellerId': sellerId,
        'buyerId': buyerId,
        'names': names,
        'participants': participants,
        'lastMessage': lastMessage,
        'lastSenderId': lastSenderId,
        'updatedAt': updatedAt,
        'unreadBy': unreadBy,
      };
}

/// Message d'une conversation : `conversations/{id}/messages/{messageId}`.
class ChatMessage {
  static const int maxLength = 1000;

  final String id;
  final String senderId;
  final String text;
  final DateTime sentAt;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.sentAt,
  });

  factory ChatMessage.fromMap(String id, Map<String, dynamic> map) => ChatMessage(
        id: id,
        senderId: map['senderId'] ?? '',
        text: map['text'] ?? '',
        // Un message tout juste envoyé n'a pas encore d'horodatage serveur.
        sentAt: _date(map['sentAt']) ?? DateTime.now(),
      );
}
