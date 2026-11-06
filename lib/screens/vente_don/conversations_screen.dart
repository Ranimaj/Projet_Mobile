import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_tokens.dart';
import '../../models/conversation_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/chat_service.dart';
import '../../widgets/empty_state.dart';
import 'chat_screen.dart';

/// Libellé court d'une date de message : heure aujourd'hui, « hier », sinon
/// jour et mois.
String chatDateLabel(DateTime at, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final d = DateTime(at.year, at.month, at.day);
  final t = DateTime(today.year, today.month, today.day);
  final diff = t.difference(d).inDays;
  if (diff == 0) return DateFormat('HH:mm').format(at);
  if (diff == 1) return 'Hier';
  return DateFormat('d MMM', 'fr_FR').format(at);
}

/// Messages Vente & Don de l'utilisateur : une ligne par conversation
/// (article, interlocuteur, dernier message, non-lu).
class ConversationsScreen extends StatefulWidget {
  final ChatService? chatService;
  const ConversationsScreen({super.key, this.chatService});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  late final ChatService _chat = widget.chatService ?? ChatService();
  Stream<List<ConversationModel>>? _stream;
  String? _uid;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uid = context.read<AuthProvider>().currentUser?.id;
    if (uid != _uid) {
      _uid = uid;
      _stream = uid == null ? null : _chat.watchConversations(uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Mes messages')),
      body: uid == null || _stream == null
          ? const EmptyState(
              icon: Icons.lock_outline_rounded,
              title: 'Connexion requise',
              subtitle: 'Connecte-toi pour voir tes messages.',
            )
          : StreamBuilder<List<ConversationModel>>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.hasError) {
                  return const EmptyState(
                    icon: Icons.wifi_off_rounded,
                    title: 'Messages indisponibles',
                    subtitle: 'Vérifie ta connexion et réessaie.',
                  );
                }
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final list = snap.data!;
                if (list.isEmpty) {
                  return const EmptyState(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'Aucune conversation',
                    subtitle: 'Contacte un vendeur depuis la fiche d\'un article.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 84),
                  itemBuilder: (context, i) => _ConversationTile(
                    conversation: list[i],
                    me: uid,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ChatScreen(conversation: list[i], chatService: _chat),
                    )),
                  ),
                );
              },
            ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final ConversationModel conversation;
  final String me;
  final VoidCallback onTap;

  const _ConversationTile({required this.conversation, required this.me, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final unread = conversation.isUnreadFor(me);
    final url = conversation.articleImageUrl;
    final role = me == conversation.sellerId ? 'Acheteur' : 'Vendeur';
    final preview = conversation.lastMessage.isEmpty
        ? 'Nouvelle conversation'
        : '${conversation.lastSenderId == me ? 'Toi : ' : ''}${conversation.lastMessage}';

    return ListTile(
      key: ValueKey('conversation-${conversation.id}'),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 52,
          height: 52,
          child: url == null
              ? ColoredBox(
                  color: t.primarySoft,
                  child: Icon(Icons.shopping_bag_outlined, color: t.primary),
                )
              : CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
        ),
      ),
      title: Text(
        '${conversation.otherName(me)} · $role',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.titleSmall?.copyWith(fontWeight: unread ? FontWeight.w800 : FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(conversation.articleTitle,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: text.labelMedium),
          Text(
            preview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodyMedium?.copyWith(
              color: unread ? t.textPrimary : t.textSecondary,
              fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(chatDateLabel(conversation.updatedAt), style: text.labelMedium),
          if (unread) ...[
            const SizedBox(height: 6),
            Container(
              key: const Key('unread-dot'),
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: t.primary, shape: BoxShape.circle),
            ),
          ],
        ],
      ),
    );
  }
}
