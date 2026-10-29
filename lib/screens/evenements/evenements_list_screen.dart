import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/constants/app_constants.dart';
import '../../models/event_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/event_provider.dart';
import '../../widgets/offline_banner.dart';
import 'add_event_screen.dart';
import 'event_calendar_screen.dart';
import 'event_card.dart';
import 'event_categories.dart';
import 'event_hero_card.dart';
import 'location_service.dart';
import 'event_rules.dart';
import 'event_style.dart';

/// BF8.1 — liste des événements.
/// En-tête : recherche (icône qui s'ouvre en champ), calendrier, filtres
/// (catégories dans une feuille du bas, badge = nombre de filtres actifs).
/// Onglets : À venir · Passés · Mes inscriptions · Mes événements.
/// Sur « À venir » : bande des jours et carte « Prochain événement ».
class EvenementsListScreen extends StatefulWidget {
  const EvenementsListScreen({super.key});

  @override
  State<EvenementsListScreen> createState() => _EvenementsListScreenState();
}

class _EvenementsListScreenState extends State<EvenementsListScreen> with TickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  final _stripCtrl = ScrollController();
  Timer? _debounce;
  String _query = '';
  bool _searching = false;

  TabController? _tabCtrl;
  List<EventFilter> _tabs = const [];

  static const _tabLabels = {
    EventFilter.upcoming: 'À venir',
    EventFilter.past: 'Passés',
    EventFilter.myRegistrations: 'Mes inscriptions',
    EventFilter.myEvents: 'Mes événements',
  };

  /// Largeur d'une case de la bande des jours (52) + espace (8).
  static const double _dayItemExtent = 60;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EventProvider>().load();
      _scrollStripToFocusDay();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _stripCtrl.dispose();
    _tabCtrl?.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ Onglets

  /// Les visiteurs n'ont que « À venir » et « Passés » : on recrée le
  /// contrôleur d'onglets quand la liste d'onglets change.
  void _syncTabs(List<EventFilter> tabs, EventProvider provider) {
    if (_tabCtrl != null && _tabs.length == tabs.length) return;
    // L'ancien contrôleur est libéré après l'image : le TabBar s'en détache
    // pendant cette reconstruction.
    final old = _tabCtrl;
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    _tabs = tabs;
    final index = tabs.indexOf(provider.filter);
    _tabCtrl = TabController(length: tabs.length, vsync: this, initialIndex: index < 0 ? 0 : index);
    if (index < 0) {
      // Ex. « Mes inscriptions » choisi puis déconnexion : retour à « À venir ».
      WidgetsBinding.instance.addPostFrameCallback((_) => provider.setFilter(EventFilter.upcoming));
    }
  }

  // ---------------------------------------------------------- Recherche

  /// Recherche « debouncée » : on attend que l'utilisateur arrête de taper
  /// (AppConstants.debounceDuration) avant de filtrer.
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(AppConstants.debounceDuration, () {
      if (mounted) setState(() => _query = value);
    });
  }

  void _openSearch() {
    setState(() => _searching = true);
    _searchFocus.requestFocus();
  }

  void _closeSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    setState(() {
      _searching = false;
      _query = '';
    });
  }

  /// « Voir tous les événements » : on enlève recherche, catégorie et jour,
  /// et on revient sur « À venir ».
  void _resetAll(EventProvider provider) {
    _closeSearch();
    provider
      ..setFilter(EventFilter.upcoming)
      ..setCategoryFilter(null)
      ..setSelectedDay(null)
      ..setPriceFilter(PriceFilter.all)
      ..setSortByDate();
    _tabCtrl?.animateTo(0);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollStripToFocusDay());
  }

  // ---------------------------------------------------- Jours / calendrier

  /// Jour mis en avant dans la bande : le jour sélectionné, sinon aujourd'hui.
  DateTime get _focusDay => context.read<EventProvider>().selectedDay ?? DateTime.now();

  /// Fait défiler la bande pour montrer le jour sélectionné (ou aujourd'hui).
  void _scrollStripToFocusDay() {
    if (!_stripCtrl.hasClients) return;
    final offset = (_focusDay.day - 1) * _dayItemExtent;
    _stripCtrl.jumpTo(offset.clamp(0, _stripCtrl.position.maxScrollExtent));
  }

  Future<void> _openCalendar() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EventCalendarScreen()));
    // Au retour, la bande montre le mois et le jour choisis dans le calendrier.
    if (mounted) WidgetsBinding.instance.addPostFrameCallback((_) => _scrollStripToFocusDay());
  }

  void _openFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // Hauteur selon le contenu (et défilement si l'écran est petit).
      isScrollControlled: true,
      builder: (_) => const _CategorySheet(),
    ).then((_) {
      if (mounted) WidgetsBinding.instance.addPostFrameCallback((_) => _scrollStripToFocusDay());
    });
  }

  // ---------------------------------------------------------------- Build

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EventProvider>();
    final auth = context.watch<AuthProvider>();
    final isGuest = auth.status != AuthStatus.authenticated;
    final userId = auth.currentUser?.id;
    _syncTabs(isGuest ? const [EventFilter.upcoming, EventFilter.past] : EventFilter.values, provider);

    final now = DateTime.now();
    final events = provider.visibleEvents(userId, query: _query);
    final isUpcoming = provider.filter == EventFilter.upcoming;

    // Carte « Prochain événement » : seulement sur « À venir », sans recherche
    // ni jour choisi ; c'est le premier événement qui n'a pas encore commencé.
    EventModel? hero;
    if (isUpcoming && _query.isEmpty && provider.selectedDay == null) {
      for (final e in events) {
        if (now.isBefore(e.startDate)) {
          hero = e;
          break;
        }
      }
    }
    final listEvents = hero == null ? events : events.where((e) => e.id != hero!.id).toList();

    return Scaffold(
      appBar: _buildAppBar(provider),
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
            _buildTabBar(provider),
            if (isUpcoming) _buildDayStrip(provider, userId),
            if (provider.loadError != null && events.isNotEmpty) _buildStaleBanner(provider),
            Expanded(child: _buildBody(provider, listEvents, hero, userId, now)),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(EventProvider provider) {
    final t = AppTokens.of(context);
    final activeFilters =
        EventRules.activeFilterCount(
            category: provider.categoryFilter, day: provider.selectedDay, price: provider.priceFilter);
    final filterButton = IconButton(
      tooltip: activeFilters == 0 ? 'Filtres' : 'Filtres ($activeFilters actif(s))',
      onPressed: _openFilterSheet,
      icon: Badge(
        isLabelVisible: activeFilters > 0,
        label: Text('$activeFilters'),
        backgroundColor: t.primary,
        child: const Icon(Icons.tune_rounded),
      ),
    );
    final calendarButton = IconButton(
      tooltip: 'Vue calendrier',
      icon: const Icon(Icons.calendar_month_outlined),
      onPressed: _openCalendar,
    );

    if (_searching) {
      return AppBar(
        leading: IconButton(tooltip: 'Fermer la recherche', icon: const Icon(Icons.arrow_back), onPressed: _closeSearch),
        title: TextField(
          controller: _searchCtrl,
          focusNode: _searchFocus,
          onChanged: _onSearchChanged,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Titre ou lieu…',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
        ),
        actions: [calendarButton, filterButton],
      );
    }
    return AppBar(
      title: const Text('Événements'),
      actions: [
        IconButton(tooltip: 'Rechercher', icon: const Icon(Icons.search_rounded), onPressed: _openSearch),
        calendarButton,
        filterButton,
      ],
    );
  }

  Widget _buildTabBar(EventProvider provider) {
    final t = AppTokens.of(context);
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.outline))),
      child: TabBar(
        controller: _tabCtrl,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: t.primary,
        unselectedLabelColor: t.textSecondary,
        indicatorColor: t.primary,
        indicatorWeight: 3,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        onTap: (i) => provider.setFilter(_tabs[i]),
        tabs: [
          for (final f in _tabs)
            Tab(
              height: 48,
              child: Semantics(label: 'Onglet ${_tabLabels[f]}', excludeSemantics: true, child: Text(_tabLabels[f]!)),
            ),
        ],
      ),
    );
  }

  /// Bande compacte des jours du mois (À venir uniquement) : point sous les
  /// jours qui ont des événements, aujourd'hui entouré.
  Widget _buildDayStrip(EventProvider provider, String? userId) {
    final t = AppTokens.of(context);
    final selected = provider.selectedDay == null ? null : EventRules.dateOnly(provider.selectedDay!);
    final focus = selected ?? DateTime.now();
    final month = DateTime(focus.year, focus.month);
    final today = EventRules.dateOnly(DateTime.now());
    final eventDays = EventRules.eventDays(provider.calendarEvents(userId));
    final monthLabel = DateFormat.yMMMM('fr_FR').format(month);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Text(monthLabel[0].toUpperCase() + monthLabel.substring(1),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: t.textSecondary)),
        ),
        SizedBox(
          height: 66,
          child: ListView.builder(
            controller: _stripCtrl,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
            itemCount: EventRules.daysInMonth(month),
            itemExtent: _dayItemExtent,
            itemBuilder: (context, i) {
              final day = DateTime(month.year, month.month, i + 1);
              final isSelected = day == selected;
              final hasEvents = eventDays.contains(day);
              final isToday = day == today;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Semantics(
                  button: true,
                  selected: isSelected,
                  label: DateFormat('EEEE d MMMM', 'fr_FR').format(day) + (hasEvents ? ', avec événements' : ''),
                  excludeSemantics: true,
                  child: Material(
                    color: isSelected ? t.primary : t.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: isSelected || isToday ? t.primary : t.outline),
                    ),
                    child: InkWell(
                      customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      onTap: () {
                        provider.setSelectedDay(isSelected ? null : day);
                        // Désélection : la bande peut revenir au mois courant.
                        if (isSelected) {
                          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollStripToFocusDay());
                        }
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(DateFormat('E', 'fr_FR').format(day).toUpperCase(),
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? t.onPrimary.withValues(alpha: 0.7) : t.textSecondary)),
                          Text('${day.day}',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected ? t.onPrimary : t.textPrimary)),
                          const SizedBox(height: 2),
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: !hasEvents
                                  ? Colors.transparent
                                  : (isSelected ? t.onPrimary : t.primary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Échec d'actualisation mais des données en cache : on les montre avec un bandeau.
  Widget _buildStaleBanner(EventProvider provider) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(10)),
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

  Widget _buildBody(
      EventProvider provider, List<EventModel> events, EventModel? hero, String? userId, DateTime now) {
    if (provider.isLoading && events.isEmpty && hero == null) return const _ShimmerList();

    // Vide ou erreur : on garde un défilement pour le « tirer pour actualiser ».
    if (events.isEmpty && hero == null) {
      final hasError = provider.loadError != null;
      return RefreshIndicator(
        onRefresh: provider.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 56),
          children: [
            _StateMessage(
              icon: hasError ? Icons.cloud_off_rounded : Icons.event_busy_outlined,
              message: hasError ? provider.loadError! : _emptyMessage(provider),
              buttonLabel: hasError ? 'Réessayer' : 'Voir tous les événements',
              onPressed: hasError ? provider.load : () => _resetAll(provider),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: provider.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
        children: [
          if (hero != null) ...[
            EventHeroCard(event: hero, now: now, distanceMeters: provider.distanceTo(hero)),
            if (events.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Ensuite', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
            ],
          ],
          for (final e in events) ...[
            EventCard(
              event: e,
              now: now,
              isRegistered: userId != null && e.isUserRegistered(userId),
              distanceMeters: provider.distanceTo(e),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  /// Une ligne propre au filtre actif (règle 11). Priorité : recherche,
  /// jour, catégorie, puis onglet.
  String _emptyMessage(EventProvider provider) {
    if (_query.isNotEmpty) return 'Aucun résultat pour « $_query ».';
    if (provider.selectedDay != null) return 'Aucun événement ce jour.';
    if (provider.categoryFilter != null) return 'Aucun événement « ${provider.categoryFilter} ».';
    switch (provider.filter) {
      case EventFilter.upcoming:
        return 'Aucun événement à venir pour le moment.';
      case EventFilter.past:
        return 'Aucun événement passé.';
      case EventFilter.myRegistrations:
        return "Vous n'êtes inscrit à aucun événement.";
      case EventFilter.myEvents:
        return "Vous n'avez créé aucun événement.";
    }
  }
}

/// Feuille du bas des catégories : « Toutes » + les 5 catégories (couleur de
/// chacune) et « Réinitialiser » (catégorie et jour). Les choix s'appliquent
/// tout de suite.
class _CategorySheet extends StatelessWidget {
  const _CategorySheet();

  /// « Près de moi » : position une fois (ou celle de moins de 5 min). Refus
  /// ou indisponible : on ferme la feuille, on explique (avec l'accès aux
  /// réglages si utile) et le tri revient à la date.
  Future<void> _chooseNearMe(BuildContext context, EventProvider provider) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final failure = await provider.enableNearMe();
    if (failure == null) return;
    navigator.pop(); // la SnackBar s'affiche sur la liste, pas derrière la feuille
    final SnackBarAction? action = switch (failure.error) {
      PositionError.deniedForever =>
        const SnackBarAction(label: 'Ouvrir les réglages', onPressed: LocationService.openAppSettings),
      PositionError.serviceOff =>
        const SnackBarAction(label: 'Ouvrir les réglages', onPressed: LocationService.openLocationSettings),
      _ => null,
    };
    messenger.showSnackBar(SnackBar(
      content: Text('${failure.message} Tri par date conservé.'),
      action: action,
      duration: const Duration(seconds: 6),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EventProvider>();
    // Le contenu défile si la place manque (petit écran, clavier ouvert) :
    // les boutons du bas ne sont jamais coupés.
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Catégories', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                EventChip(
                  label: 'Toutes',
                  selected: provider.categoryFilter == null,
                  onTap: () => provider.setCategoryFilter(null),
                ),
                for (final c in EventCategories.all)
                  EventChip(
                    label: c,
                    color: EventStyle.categoryColor(c),
                    selected: provider.categoryFilter == c,
                    onTap: () => provider.setCategoryFilter(provider.categoryFilter == c ? null : c),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text('Prix', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (value, label) in const [
                  (PriceFilter.all, 'Tous'),
                  (PriceFilter.free, 'Gratuit'),
                  (PriceFilter.paid, 'Payant'),
                ])
                  EventChip(
                    label: label,
                    selected: provider.priceFilter == value,
                    onTap: () => provider.setPriceFilter(value),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text('Trier par', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text("« Près de moi » trie l'onglet À venir par distance.",
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                EventChip(
                  label: 'Date',
                  selected: provider.sort == EventSort.date,
                  onTap: provider.setSortByDate,
                ),
                EventChip(
                  label: 'Près de moi',
                  selected: provider.sort == EventSort.nearMe,
                  onTap: provider.locating ? () {} : () => _chooseNearMe(context, provider),
                ),
                if (provider.locating) ...[
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  const Text('Localisation…'),
                ],
              ],
            ),
            if (provider.selectedDay != null) ...[
              const SizedBox(height: 14),
              Text('Jour choisi : ${DateFormat('EEEE d MMMM', 'fr_FR').format(provider.selectedDay!)}',
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: 16),
            // Côte à côte si ça tient, sinon l'un sous l'autre (grand texte).
            OverflowBar(
              alignment: MainAxisAlignment.spaceBetween,
              overflowAlignment: OverflowBarAlignment.end,
              spacing: 8,
              overflowSpacing: 8,
              children: [
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  onPressed: () => provider
                    ..setCategoryFilter(null)
                    ..setSelectedDay(null)
                    ..setPriceFilter(PriceFilter.all)
                    ..setSortByDate(),
                  child: const Text('Réinitialiser'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Afficher'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// État vide ou erreur : petite icône, une ligne, un bouton.
class _StateMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;
  const _StateMessage({required this.icon, required this.message, required this.buttonLabel, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: t.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
          child: Icon(icon, size: 26, color: t.primary),
        ),
        const SizedBox(height: 14),
        Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 16),
        FilledButton.tonal(
          style: FilledButton.styleFrom(minimumSize: const Size(44, 44)),
          onPressed: onPressed,
          child: Text(buttonLabel),
        ),
      ],
    );
  }
}

/// Chargement : cartes « squelette » animées (dont la grande carte du haut).
class _ShimmerList extends StatelessWidget {
  const _ShimmerList();

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE5E7EB),
      highlightColor: const Color(0xFFF9FAFB),
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        children: [
          Container(
            height: 150,
            decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(20)),
          ),
          for (var i = 0; i < 4; i++) ...[
            const SizedBox(height: 12),
            Container(
              height: 96,
              decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(EventCard.radius)),
            ),
          ],
        ],
      ),
    );
  }
}
