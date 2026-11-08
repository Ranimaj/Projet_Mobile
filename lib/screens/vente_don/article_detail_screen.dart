import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/theme/module_colors.dart';
import '../../core/utils/geo.dart';
import '../../models/article_model.dart';
import '../../providers/article_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/ai/chat_replier.dart';
import '../../services/chat_service.dart';
import '../../widgets/hero_sheet_scaffold.dart';
import '../../widgets/initials_avatar.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/round_icon_button.dart';
import '../../widgets/status_chip.dart';
import 'article_form_screen.dart';
import 'chat_screen.dart';
import 'widgets/article_card.dart';
import 'widgets/article_photo.dart';
import 'widgets/fraud_risk_card.dart';

/// BF4 — détail d'un article : photos, prix, description, vendeur, vues et
/// distance. Le propriétaire modifie, réserve, termine ou supprime ; les
/// autres ajoutent aux favoris et contactent le vendeur.
class ArticleDetailScreen extends StatefulWidget {
  final ArticleModel article;
  final ChatService? chatService;
  final ChatReplier? chatReplier;

  const ArticleDetailScreen({super.key, required this.article, this.chatService, this.chatReplier});

  @override
  State<ArticleDetailScreen> createState() => _ArticleDetailScreenState();
}

class _ArticleDetailScreenState extends State<ArticleDetailScreen> {
  final _pages = PageController();
  int _page = 0;
  bool _contacting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      final uid = auth.status == AuthStatus.authenticated ? auth.currentUser?.id : null;
      context.read<ArticleProvider>().recordView(widget.article.id, uid);
    });
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _contact(ArticleModel article) async {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user == null) return;
    setState(() => _contacting = true);
    final chat = widget.chatService ?? ChatService();
    try {
      final conversation = await chat.openConversation(
        article: article,
        buyerId: user.id,
        buyerName: user.fullName,
      );
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(conversation: conversation, chatService: chat, replier: widget.chatReplier),
      ));
    } catch (_) {
      if (mounted) _snack('Impossible d\'ouvrir la conversation. Réessaie.');
    } finally {
      if (mounted) setState(() => _contacting = false);
    }
  }

  Future<void> _ownerActions(ArticleModel article) async {
    final provider = context.read<ArticleProvider>();
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('action-edit'),
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Modifier'),
              onTap: () => Navigator.pop(sheet, 'edit'),
            ),
            if (article.status != ArticleStatus.available)
              ListTile(
                key: const Key('action-available'),
                leading: const Icon(Icons.undo_rounded),
                title: const Text('Remettre disponible'),
                onTap: () => Navigator.pop(sheet, 'available'),
              ),
            if (article.status == ArticleStatus.available)
              ListTile(
                key: const Key('action-reserve'),
                leading: const Icon(Icons.bookmark_outline_rounded),
                title: const Text('Marquer comme réservé'),
                onTap: () => Navigator.pop(sheet, 'reserve'),
              ),
            if (article.status != ArticleStatus.done)
              ListTile(
                key: const Key('action-done'),
                leading: const Icon(Icons.check_circle_outline_rounded),
                title: Text(article.isFree ? 'Marquer comme donné' : 'Marquer comme vendu'),
                onTap: () => Navigator.pop(sheet, 'done'),
              ),
            ListTile(
              key: const Key('action-delete'),
              leading: Icon(Icons.delete_outline_rounded, color: AppTokens.of(sheet).danger),
              title: Text('Supprimer', style: TextStyle(color: AppTokens.of(sheet).danger)),
              onTap: () => Navigator.pop(sheet, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'edit':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ArticleFormScreen(article: article)),
        );
      case 'available':
        await provider.markAsAvailable(article.id);
        if (!mounted) return;
        _snack('Article de nouveau disponible.');
      case 'reserve':
        await provider.markAsReserved(article.id);
        if (!mounted) return;
        _snack('Article marqué comme réservé.');
      case 'done':
        await provider.markAsDone(article.id);
        if (!mounted) return;
        _snack(article.isFree ? 'Article marqué comme donné.' : 'Article marqué comme vendu.');
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('Supprimer l\'article ?'),
            content: const Text('Cette action est définitive.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Annuler')),
              TextButton(
                key: const Key('confirm-delete'),
                onPressed: () => Navigator.pop(d, true),
                child: const Text('Supprimer'),
              ),
            ],
          ),
        );
        if (ok != true) return;
        await provider.deleteArticle(article.id);
        if (!mounted) return;
        _snack('Article supprimé.');
        Navigator.of(context).pop();
    }
  }

  Widget _hero(ArticleModel article, AppTokens t) {
    if (article.imageUrls.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [ModuleColors.marketSoft, t.primarySoft],
          ),
        ),
        child: Center(child: Icon(Icons.shopping_bag_outlined, size: 56, color: t.primary)),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          key: const Key('photo-pager'),
          controller: _pages,
          itemCount: article.imageUrls.length,
          onPageChanged: (i) => setState(() => _page = i),
          itemBuilder: (_, i) => ArticlePhoto(url: article.imageUrls[i]),
        ),
        if (article.imageUrls.length > 1)
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < article.imageUrls.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: i == _page ? 1 : 0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ArticleProvider>();
    final auth = context.watch<AuthProvider>();
    final article = provider.byId(widget.article.id) ?? widget.article;
    final user = auth.status == AuthStatus.authenticated ? auth.currentUser : null;
    final isOwner = user != null && user.id == article.ownerId;
    final isFav = article.isFavoriteOf(user?.id);
    final distance = provider.distanceKmTo(article);
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final date = DateFormat('d MMM yyyy', 'fr_FR').format(article.createdAt);

    Widget? bottomBar;
    if (isOwner) {
      bottomBar = PillButton(
        key: const Key('edit-article'),
        label: 'Modifier l\'article',
        icon: Icons.edit_outlined,
        style: PillStyle.ghost,
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => ArticleFormScreen(article: article))),
      );
    } else if (user != null && article.status != ArticleStatus.done) {
      bottomBar = PillButton(
        key: const Key('contact-seller'),
        label: 'Contacter ${article.ownerName.split(' ').first}',
        icon: Icons.chat_bubble_outline_rounded,
        isLoading: _contacting,
        onPressed: () => _contact(article),
      );
    } else if (user == null) {
      bottomBar = Text(
        'Connecte-toi pour contacter le vendeur.',
        textAlign: TextAlign.center,
        style: text.bodyMedium,
      );
    }

    return HeroSheetScaffold(
      hero: _hero(article, t),
      heroLeading: RoundIconButton(
        icon: Icons.arrow_back_rounded,
        tooltip: 'Retour',
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      heroActions: [
        if (user != null && !isOwner)
          RoundIconButton(
            key: const Key('toggle-favorite'),
            icon: isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            tooltip: isFav ? 'Retirer des favoris' : 'Ajouter aux favoris',
            onPressed: () => provider.toggleFavorite(article.id, user.id),
          ),
        if (isOwner)
          RoundIconButton(
            key: const Key('owner-menu'),
            icon: Icons.more_horiz_rounded,
            tooltip: 'Gérer l\'article',
            onPressed: () => _ownerActions(article),
          ),
      ],
      bottomBar: bottomBar,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            articleStatusChip(article),
            StatusChip(label: article.category, style: StatusChipStyle.neutral),
          ],
        ),
        const SizedBox(height: 12),
        Text(article.title, key: const Key('article-title'), style: text.headlineMedium),
        const SizedBox(height: 6),
        Text(
          article.priceLabel,
          key: const Key('article-price'),
          style: text.headlineMedium?.copyWith(color: article.isFree ? t.success : t.primary),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            _Meta(icon: Icons.calendar_today_outlined, text: 'Publié le $date'),
            _Meta(
              key: const Key('article-views'),
              icon: Icons.visibility_outlined,
              text: article.viewCount <= 1 ? '${article.viewCount} vue' : '${article.viewCount} vues',
            ),
            if (article.favoritedBy.isNotEmpty)
              _Meta(
                icon: Icons.favorite_border_rounded,
                text: '${article.favoritedBy.length} favori${article.favoritedBy.length > 1 ? 's' : ''}',
              ),
            if (distance != null)
              _Meta(
                key: const Key('article-distance'),
                icon: Icons.place_outlined,
                text: 'À ${formatDistance(distance)} de toi',
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text('Description', style: text.titleMedium),
        const SizedBox(height: 6),
        Text(article.description, style: text.bodyLarge),
        if (!isOwner) ...[
          const SizedBox(height: 16),
          FraudRiskCard(article: article),
        ],
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.surfaceMuted,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              InitialsAvatar(initials: _initials(article.ownerName), size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(isOwner ? 'Toi' : article.ownerName, style: text.titleSmall),
                    Text(isOwner ? 'Tu as publié cet article' : 'Vendeur', style: text.labelMedium),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Meta({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: t.textSecondary),
        const SizedBox(width: 4),
        Text(text, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}
