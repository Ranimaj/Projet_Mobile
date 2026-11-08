import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_tokens.dart';
import '../../models/conversation_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/chat_service.dart';
import '../../widgets/round_icon_button.dart';

/// Conversation acheteur ↔ vendeur à propos d'un article (temps réel).
class ChatScreen extends StatefulWidget {
  final ConversationModel conversation;
  final ChatService? chatService;

  const ChatScreen({super.key, required this.conversation, this.chatService});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatService _chat = widget.chatService ?? ChatService();
  late final Stream<List<ChatMessage>> _messages = _chat.watchMessages(widget.conversation.id);
  final _input = TextEditingController();
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
                    return _Bubble(message: m, mine: m.senderId == me);
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
  const _Bubble({required this.message, required this.mine});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final fg = mine ? t.onPrimary : t.textPrimary;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          decoration: BoxDecoration(
            color: mine ? t.primary : t.surfaceMuted,
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
