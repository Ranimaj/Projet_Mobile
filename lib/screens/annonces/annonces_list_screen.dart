import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/annonce_filter.dart';
import '../../providers/annonce_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/notification_service.dart';
import '../../widgets/annonce_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/filter_chip_pill.dart';
import '../../widgets/offline_banner.dart';
import 'add_annonce_screen.dart';
import 'annonce_detail_screen.dart';

/// Fil d'annonces campus : recherche, filtres (catégorie, urgentes,
/// "pour moi", "mes annonces"), épinglage automatique des officielles,
/// réception des notifications push ciblées.
///
/// La recherche et les filtres « vue » sont de l'état local de l'écran
/// ([AnnonceFilter]) ; seul le filtre par catégorie passe par le provider.
class AnnoncesListScreen extends StatefulWidget {
  const AnnoncesListScreen({super.key});

  @override
  State<AnnoncesListScreen> createState() => _AnnoncesListScreenState();
}

class _AnnoncesListScreenState extends State<AnnoncesListScreen> {
  final _searchCtrl = TextEditingController();
  final _notifications = NotificationService();
  StreamSubscription<PushEvent>? _pushSub;

  AnnonceFilter _filter = const AnnonceFilter();
  late bool _pushEnabled;
  bool _loadedOnce = false;

  @override
  void initState() {
    super.initState();
    _pushEnabled = _notifications.pushEnabled;
    _notifications.openedAnnonceId.addListener(_consumeOpenedNotification);
    _pushSub = _notifications.onForeground.listen(_onForegroundPush);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<AnnonceProvider>().load();
      if (!mounted) return;
      setState(() => _loadedOnce = true);
      _consumeOpenedNotification();
    });
  }

  @override
  void dispose() {
    _notifications.openedAnnonceId.removeListener(_consumeOpenedNotification);
    _pushSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openDetail(String annonceId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AnnonceDetailScreen(annonceId: annonceId)),
    );
  }

  /// Clic sur une notification -> ouvre l'annonce correspondante.
  Future<void> _consumeOpenedNotification() async {
    final id = _notifications.openedAnnonceId.value;
    if (id == null || !mounted) return;
    _notifications.openedAnnonceId.value = null;

    final provider = context.read<AnnonceProvider>();
    if (provider.byId(id) == null) await provider.load();
    if (!mounted) return;
    if (provider.byId(id) == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Cette annonce n'est plus disponible.")));
      return;
    }
    _openDetail(id);
  }

  /// Notification reçue app ouverte -> bandeau + rafraîchissement du fil.
  Future<void> _onForegroundPush(PushEvent event) async {
    if (!mounted) return;
    final annonceId = event.annonceId;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(event.title ?? 'Nouvelle annonce'),
      action: annonceId == null
          ? null
          : SnackBarAction(label: 'Voir', onPressed: () => _openOrLoad(annonceId)),
    ));
    await context.read<AnnonceProvider>().load();
  }

  Future<void> _openOrLoad(String id) async {
    final provider = context.read<AnnonceProvider>();
    if (provider.byId(id) == null) await provider.load();
    if (!mounted) return;
    if (provider.byId(id) == null) return;
    _openDetail(id);
  }

  Future<void> _togglePush() async {
    final enable = !_pushEnabled;
    await context.read<AnnonceProvider>().setPushEnabled(enable);
    if (!mounted) return;
    setState(() => _pushEnabled = enable);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(enable
          ? 'Notifications d’annonces activées'
          : 'Notifications d’annonces désactivées'),
    ));
  }

  void _resetFilters() {
    _searchCtrl.clear();
    setState(() => _filter = const AnnonceFilter());
    context.read<AnnonceProvider>().setCategoryFilter(null);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final provider = context.watch<AnnonceProvider>();
    final auth = context.watch<AuthProvider>();
    final isGuest = auth.status != AuthStatus.authenticated;

    final all = provider.items; // déjà filtré par catégorie, épinglées d'abord
    final items = _filter.apply(all, user: auth.currentUser);
    final categoryActive = provider.categoryFilter != null;
    final activeCount = _filter.activeCount + (categoryActive ? 1 : 0);
    final showInitialLoader = provider.isLoading && !_loadedOnce && all.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Annonces'),
        actions: [
          if (!isGuest)
            IconButton(
              tooltip: _pushEnabled
                  ? 'Désactiver les notifications'
                  : 'Activer les notifications',
              icon: Icon(_pushEnabled
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_off_outlined),
              onPressed: _togglePush,
            ),
        ],
      ),
      floatingActionButton: isGuest
          ? null
          : FloatingActionButton(
              tooltip: 'Publier une annonce',
              backgroundColor: t.primary,
              foregroundColor: t.onPrimary,
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const AddAnnonceScreen())),
              child: const Icon(Icons.add_rounded),
            ),
      body: SafeArea(
        child: Column(
          children: [
            const OfflineBanner(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _filter = _filter.copyWith(query: v)),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Rechercher une annonce…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Effacer la recherche',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _filter = _filter.copyWith(query: ''));
                          },
                        ),
                ),
              ),
            ),
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                children: [
                  _chip(FilterChipPill(
                      label: 'Toutes',
                      selected: provider.categoryFilter == null,
                      onTap: () => provider.setCategoryFilter(null))),
                  ...AppConstants.annonceCategories.map((c) => _chip(FilterChipPill(
                        label: c,
                        selected: provider.categoryFilter == c,
                        onTap: () => provider
                            .setCategoryFilter(provider.categoryFilter == c ? null : c),
                      ))),
                  _chip(FilterChipPill(
                      label: 'Urgentes',
                      icon: Icons.priority_high_rounded,
                      selected: _filter.onlyUrgent,
                      onTap: () => setState(
                          () => _filter = _filter.copyWith(onlyUrgent: !_filter.onlyUrgent)))),
                  if (!isGuest) ...[
                    _chip(FilterChipPill(
                        label: 'Pour moi',
                        icon: Icons.person_pin_circle_outlined,
                        selected: _filter.onlyForMe,
                        onTap: () => setState(
                            () => _filter = _filter.copyWith(onlyForMe: !_filter.onlyForMe)))),
                    _chip(FilterChipPill(
                        label: 'Mes annonces',
                        icon: Icons.edit_note_rounded,
                        selected: _filter.onlyMine,
                        onTap: () => setState(
                            () => _filter = _filter.copyWith(onlyMine: !_filter.onlyMine)))),
                  ],
                ],
              ),
            ),
            if (activeCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${items.length} résultat${items.length > 1 ? 's' : ''}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    TextButton(onPressed: _resetFilters, child: const Text('Réinitialiser')),
                  ],
                ),
              ),
            Expanded(
              child: showInitialLoader
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: provider.load,
                      child: items.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                EmptyState(
                                  icon: activeCount > 0
                                      ? Icons.search_off_rounded
                                      : Icons.campaign_outlined,
                                  title: activeCount > 0 ? 'Aucun résultat' : 'Aucune annonce',
                                  subtitle: activeCount > 0
                                      ? 'Essayez de modifier ou de réinitialiser vos filtres.'
                                      : "Les annonces officielles et du campus s'afficheront ici.",
                                ),
                              ],
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(20, 10, 20, 90),
                              itemCount: items.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, i) => AnnonceCard(
                                annonce: items[i],
                                onTap: () => _openDetail(items[i].id),
                              ),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(Widget chip) => Padding(padding: const EdgeInsets.only(right: 8), child: chip);
}
