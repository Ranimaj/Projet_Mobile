import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../models/event_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/event_provider.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/offline_banner.dart';
import 'add_event_screen.dart';
import 'event_detail_screen.dart';
import 'event_rules.dart';
import 'event_style.dart';

/// BF8.1 — liste des événements : recherche, filtres (À venir, Passés, Mes
/// inscriptions, Mes événements), catégories et jour, tous combinables.
class EvenementsListScreen extends StatefulWidget {
  const EvenementsListScreen({super.key});

  @override
  State<EvenementsListScreen> createState() => _EvenementsListScreenState();
}

class _EvenementsListScreenState extends State<EvenementsListScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<EventProvider>().load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Recherche « debouncée » : on attend que l'utilisateur arrête de taper
  /// (AppConstants.debounceDuration) avant de filtrer.
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(AppConstants.debounceDuration, () {
      if (mounted) setState(() => _query = value);
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EventProvider>();
    final auth = context.watch<AuthProvider>();
    final isGuest = auth.status != AuthStatus.authenticated;
    final userId = auth.currentUser?.id;
    final events = provider.visibleEvents(userId, query: _query);

    return Scaffold(
      appBar: AppBar(title: const Text('Événements')),
      floatingActionButton: isGuest
          ? null
          : FloatingActionButton(
              tooltip: 'Créer un événement',
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const AddEventScreen())),
              child: const Icon(Icons.add_rounded),
            ),
      body: SafeArea(
        child: Column(
          children: [
            const OfflineBanner(),
            _buildSearchField(),
            _buildFilterChips(provider, isGuest),
            _buildCategoryChips(provider),
            _buildDayStrip(provider),
            if (provider.loadError != null && events.isNotEmpty) _buildStaleBanner(provider),
            Expanded(child: _buildBody(provider, events, userId)),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Rechercher un titre ou un lieu',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchCtrl.text.isEmpty
              ? null
              : IconButton(tooltip: 'Effacer', icon: const Icon(Icons.close_rounded), onPressed: _clearSearch),
        ),
      ),
    );
  }

  Widget _buildFilterChips(EventProvider provider, bool isGuest) {
    const labels = {
      EventFilter.upcoming: 'À venir',
      EventFilter.past: 'Passés',
      EventFilter.myRegistrations: 'Mes inscriptions',
      EventFilter.myEvents: 'Mes événements',
    };
    // « Mes inscriptions / Mes événements » n'ont pas de sens pour un visiteur.
    final filters = isGuest ? [EventFilter.upcoming, EventFilter.past] : EventFilter.values;
    return _ChipRow(children: [
      for (final f in filters)
        _Chip(label: labels[f]!, selected: provider.filter == f, onTap: () => provider.setFilter(f)),
    ]);
  }

  Widget _buildCategoryChips(EventProvider provider) {
    return _ChipRow(children: [
      _Chip(
        label: 'Toutes',
        selected: provider.categoryFilter == null,
        onTap: () => provider.setCategoryFilter(null),
      ),
      for (final c in AppConstants.eventCategories)
        _Chip(
          label: c,
          color: EventStyle.categoryColor(c),
          selected: provider.categoryFilter == c,
          onTap: () => provider.setCategoryFilter(provider.categoryFilter == c ? null : c),
        ),
    ]);
  }

  Widget _buildDayStrip(EventProvider provider) {
    final today = DateTime.now();
    final selected = provider.selectedDay;
    return SizedBox(
      height: 70,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        itemCount: 14,
        itemBuilder: (context, i) {
          final day = DateTime(today.year, today.month, today.day + i);
          final isSelected = selected != null &&
              selected.year == day.year &&
              selected.month == day.month &&
              selected.day == day.day;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => provider.setSelectedDay(isSelected ? null : day),
                child: Container(
                  width: 52,
                  decoration: BoxDecoration(
                    gradient: isSelected ? AppColors.primaryGradient : null,
                    color: isSelected ? null : Colors.white,
                    border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(DateFormat('E', 'fr_FR').format(day).toUpperCase(),
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? Colors.white70 : AppColors.textSecondary)),
                      const SizedBox(height: 2),
                      Text('${day.day}',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: isSelected ? Colors.white : AppColors.textPrimary)),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Échec d'actualisation mais des données en cache : on les montre avec un bandeau.
  Widget _buildStaleBanner(EventProvider provider) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text('Données hors-ligne : actualisation impossible.',
                style: TextStyle(fontSize: 12, color: Color(0xFF92400E))),
          ),
          TextButton(onPressed: provider.load, child: const Text('Réessayer')),
        ],
      ),
    );
  }

  Widget _buildBody(EventProvider provider, List<EventModel> events, String? userId) {
    if (provider.isLoading && events.isEmpty) return const _ShimmerList();

    // Vide ou erreur : on garde un défilement pour permettre le « tirer pour actualiser ».
    if (events.isEmpty) {
      final hasError = provider.loadError != null;
      return RefreshIndicator(
        onRefresh: provider.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            EmptyState(
              icon: hasError ? Icons.cloud_off_rounded : Icons.event_outlined,
              title: hasError ? 'Chargement impossible' : _emptyTitle(provider),
              subtitle: hasError ? provider.loadError! : _emptySubtitle(provider),
            ),
            Center(
              child: hasError
                  ? FilledButton.icon(
                      onPressed: provider.load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Réessayer'),
                    )
                  : (_query.isNotEmpty
                      ? TextButton(onPressed: _clearSearch, child: const Text('Effacer la recherche'))
                      : const SizedBox.shrink()),
            ),
          ],
        ),
      );
    }

    final now = DateTime.now();
    return RefreshIndicator(
      onRefresh: provider.load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
        itemCount: events.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _EventCard(
          event: events[i],
          now: now,
          isRegistered: userId != null && events[i].isUserRegistered(userId),
        ),
      ),
    );
  }

  /// Message vide propre au filtre actif (règle 11). Priorité : recherche,
  /// jour, catégorie, puis filtre principal.
  String _emptyTitle(EventProvider provider) {
    if (_query.isNotEmpty) return 'Aucun résultat pour « $_query »';
    if (provider.selectedDay != null) return 'Aucun événement ce jour';
    if (provider.categoryFilter != null) return 'Aucun événement « ${provider.categoryFilter} »';
    switch (provider.filter) {
      case EventFilter.upcoming:
        return 'Aucun événement à venir';
      case EventFilter.past:
        return 'Aucun événement passé';
      case EventFilter.myRegistrations:
        return 'Aucune inscription';
      case EventFilter.myEvents:
        return "Vous n'avez créé aucun événement";
    }
  }

  String _emptySubtitle(EventProvider provider) {
    if (_query.isNotEmpty) return 'Essayez un autre mot (titre ou lieu).';
    if (provider.selectedDay != null || provider.categoryFilter != null) {
      return 'Changez de jour ou de catégorie.';
    }
    switch (provider.filter) {
      case EventFilter.upcoming:
        return 'Créez le premier événement du campus avec le bouton +.';
      case EventFilter.past:
        return 'Les événements terminés apparaîtront ici.';
      case EventFilter.myRegistrations:
        return "Inscrivez-vous à un événement depuis l'onglet « À venir ».";
      case EventFilter.myEvents:
        return 'Appuyez sur + pour organiser un événement.';
    }
  }
}

/// Carte d'événement façon maquette : barre de couleur de la catégorie,
/// catégorie en petites capitales, ligne horaire et badges.
class _EventCard extends StatelessWidget {
  final EventModel event;
  final DateTime now;
  final bool isRegistered;
  const _EventCard({required this.event, required this.now, required this.isRegistered});

  @override
  Widget build(BuildContext context) {
    final color = EventStyle.categoryColor(event.category);
    final when = '${DateFormat('d MMM', 'fr_FR').format(event.startDate)} · '
        '${DateFormat('HH:mm', 'fr_FR').format(event.startDate)} · ${event.location}';
    final seats = event.capacity == null
        ? '${event.registeredUserIds.length}'
        : '${event.registeredUserIds.length}/${event.capacity}';
    final badges = EventStyle.badges(event, now, isRegistered: isRegistered);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EventDetailScreen(event: event)),
        ),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 5, color: color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(event.category.toUpperCase(),
                            style: TextStyle(
                                fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: color)),
                        const SizedBox(height: 4),
                        Text(event.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Row(children: [
                          const Icon(Icons.schedule_rounded, size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(when,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium),
                          ),
                        ]),
                        if (badges.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(spacing: 6, runSpacing: 4, children: badges),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.people_alt_outlined, size: 16, color: AppColors.primary),
                      const SizedBox(height: 2),
                      Text(seats,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rangée horizontale de chips.
class _ChipRow extends StatelessWidget {
  final List<Widget> children;
  const _ChipRow({required this.children});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => children[i],
      ),
    );
  }
}

/// Chip de filtre : cible tactile d'au moins 44 px de haut (accessibilité).
class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;
  const _Chip({required this.label, required this.selected, required this.onTap, this.color = AppColors.primary});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? color : Colors.white,
        shape: StadiumBorder(side: BorderSide(color: selected ? color : AppColors.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                widthFactor: 1,
                child: Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : AppColors.textSecondary)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Chargement : cartes « squelette » animées.
class _ShimmerList extends StatelessWidget {
  const _ShimmerList();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE5E7EB),
      highlightColor: const Color(0xFFF9FAFB),
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        itemCount: 5,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, __) => Container(
          height: 96,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}
