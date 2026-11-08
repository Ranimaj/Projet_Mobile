import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_tokens.dart';
import '../../models/article_model.dart';
import '../../models/conversation_model.dart';
import '../../providers/article_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/ai/chat_assistant.dart';
import '../../services/ai/chat_replier.dart';
import '../../services/ai/gemini_api_writer.dart';
import '../../services/chat_service.dart';
import '../../widgets/round_icon_button.dart';

/// Conversation acheteur ↔ vendeur à propos d'un article (temps réel).
/// Quand l'acheteur écrit, l'assistant IA du vendeur répond tout de suite :
/// LLM Gemini par internet, ou modèle embarqué sans internet. Le vendeur peut
/// répondre ensuite.
class ChatScreen extends StatefulWidget {
  final ConversationModel conversation;
  final ChatService? chatService;

  /// Assistant qui répond à l'acheteur (par défaut : Gemini, sinon embarqué).
  final ChatReplier? replier;

  const ChatScreen({super.key, required this.conversation, this.chatService, this.replier});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatService _chat = widget.chatService ?? ChatService();
  late final Stream<List<ChatMessage>> _messages = _chat.watchMessages(widget.conversation.id);
  late final ChatReplier _replier = widget.replier ?? GeminiChatReplier(apiKey: kGeminiApiKey);
  final _input = TextEditingController();
  List<ChatMessage> _history = const [];
  bool _sending = false;

  String? get _me => context.read<AuthProvider>().currentUser?.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _markRead());
  }

  void _markRead() {
    final me = _me;
    if (me == null || !widget.conversation.isUnreadFor(me)) return;
    _chat.markRead(widget.conversation.id, me).catchError((_) {});
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final me = _me;
    final body = _input.text.trim();
    if (me == null || body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _chat.send(widget.conversation, me, body);
      _input.clear();
      if (me == widget.conversation.buyerId && mounted) unawaited(_assistantReply(body));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message non envoyé. Réessaie.')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Réponse de l'assistant IA à la question de l'acheteur.
  Future<void> _assistantReply(String question) async {
    final article = _article();
    if (article == null) return;
    final c = widget.conversation;
    final seller = (c.names[c.sellerId] ?? article.ownerName).trim().split(RegExp(r'\s+')).first;
    try {
      final answer = await _replier.reply(ChatReplyRequest(
        question: question,
        article: article,
        sellerName: seller.isEmpty ? 'Le vendeur' : seller,
        buyerId: c.buyerId,
        history: _history,
      ));
      await _chat.send(c, kAssistantId, answer);
    } catch (_) {
      // Sans assistant, la conversation continue normalement.
    }
  }

  ArticleModel? _article() {
    try {
      return context.read<ArticleProvider>().byId(widget.conversation.articleId);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final me = context.watch<AuthProvider>().currentUser?.id ?? '';
    final c = widget.conversation;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.otherName(me), style: text.titleMedium),
            Text(c.articleTitle,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: text.labelMedium),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _messages,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Text('Messages indisponibles pour le moment.', style: text.bodyMedium),
                  );
                }
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final messages = snap.data!;
                _history = messages;
                if (messages.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Écris ton premier message à propos de « ${c.articleTitle} ».',
                        textAlign: TextAlign.center,
                        style: text.bodyMedium,
                      ),
                    ),
                  );
                }
                // Liste inversée : le dernier message reste collé en bas.
                return ListView.builder(
                  key: const Key('messages'),
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final m = messages[messages.length - 1 - i];
                    return _Bubble(
                      message: m,
                      mine: m.senderId == me,
                      assistant: m.senderId == kAssistantId,
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              decoration: BoxDecoration(
                color: t.surface,
                border: Border(top: BorderSide(color: t.outline)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('message-input'),
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: ChatMessage.maxLength,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Ton message…',
                        counterText: '',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  RoundIconButton(
                    key: const Key('send-message'),
                    icon: Icons.send_rounded,
                    tooltip: 'Envoyer',
                    style: RoundButtonStyle.primary,
                    size: 44,
                    onPressed: _sending ? null : _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final bool mine;
  final bool assistant;
  const _Bubble({required this.message, required this.mine, this.assistant = false});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final fg = mine ? t.onPrimary : (assistant ? t.onPrimarySoft : t.textPrimary);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          decoration: BoxDecoration(
            color: mine ? t.primary : (assistant ? t.primarySoft : t.surfaceMuted),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mine ? 18 : 4),
              bottomRight: Radius.circular(mine ? 4 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (assistant)
                Padding(
                  key: const Key('assistant-badge'),
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.smart_toy_outlined, size: 16, color: fg),
                      const SizedBox(width: 4),
                      Text('Assistant IA', style: text.labelMedium?.copyWith(color: fg)),
                    ],
                  ),
                ),
              Text(message.text, style: text.bodyLarge?.copyWith(color: fg)),
              const SizedBox(height: 2),
              Text(
                DateFormat('HH:mm').format(message.sentAt),
                style: text.labelSmall?.copyWith(color: fg.withValues(alpha: 0.75)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
