import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/layout.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/module_colors.dart';
import '../../core/utils/activity_stats.dart';
import '../../core/utils/fr_dates.dart';
import '../../models/article_model.dart';
import '../../models/event_model.dart';
import '../../models/job_offer_model.dart';
import '../../models/user_model.dart';
import '../../providers/annonce_provider.dart';
import '../../providers/article_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/connectivity_provider.dart';
import '../../providers/event_provider.dart';
import '../../providers/job_provider.dart';
import '../../widgets/charts/area_line_chart.dart';
import '../../widgets/charts/chart_models.dart';
import '../../widgets/charts/donut_chart.dart';
import '../../widgets/featured_card.dart';
import '../../widgets/filter_chip_pill.dart';
import '../../widgets/initials_avatar.dart';
import '../../widgets/photo_card.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/round_icon_button.dart';
import '../../widgets/search_pill.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/sync_chip.dart';
import '../profile/profile_screen.dart';

/// Onglets de [AppShell], dans l'ordre de la barre de navigation.
abstract final class HomeTabs {
  static const int home = 0;
  static const int market = 1;
  static const int notices = 2;
  static const int events = 3;
  static const int jobs = 4;
}

const double _railCardWidth = 168;
const double _cardImageHeight = 100;

/// Hauteur d'un rail ou d'une cellule de carte : image + marges de la carte +
/// bloc de texte qui grandit avec la taille de texte ([extra] pour un pied).
double _cardHeight(BuildContext context, {double extra = 0}) =>
    _cardImageHeight + 24 + MediaQuery.textScalerOf(context).scale(88 + extra);

/// Hub central après connexion — BF13 : en-tête (avatar, campus, cloche),
/// date et état de synchronisation, recherche, « À la une », modules,
/// complétion du profil, événement de la semaine, stages recommandés, derniers
/// objets et activité des 7 derniers jours. Tout est calculé à partir des
/// vraies données.
class HomeScreen extends StatefulWidget {
  /// Bascule l'onglet de [AppShell] (les cartes ne poussent pas d'écran).
  final ValueChanged<int>? onNavigate;

  /// Horloge injectable (salutation, date du jour, « nouveau », « il y a »).
  final DateTime Function()? now;

  const HomeScreen({super.key, this.onNavigate, this.now});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final auth = context.read<AuthProvider>();
      if (auth.currentUser != null) {
        context.read<JobProvider>().loadMyApplications(auth.currentUser!.id);
      }
      context.read<ArticleProvider>().load();
      context.read<AnnonceProvider>().load();
      context.read<EventProvider>().load();
      context.read<JobProvider>().load();
    });
  }

  DateTime get _now => (widget.now ?? DateTime.now)();

  void _go(int tab) => widget.onNavigate?.call(tab);

  void _register(EventModel event, String userId) =>
      context.read<EventProvider>().toggleRegistration(event, userId);

  void _openProfile() => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const ProfileScreen()));

  Future<void> _search() async {
    final tab =
        await showSearch<int?>(context: context, delegate: _CampusSearch());
    if (tab != null) _go(tab);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final connectivity = context.watch<ConnectivityProvider>();
    final articles = context.watch<ArticleProvider>().items;
    final notices = context.watch<AnnonceProvider>().items;
    final events = context.watch<EventProvider>().upcoming;
    final jobs = context.watch<JobProvider>();

    final now = _now;
    final weekAgo = now.subtract(const Duration(days: 7));
    final weekAhead = now.add(const Duration(days: 7));
    final newNotices =
        notices.where((n) => n.createdAt.isAfter(weekAgo)).length;
    final officials = notices
        .where((n) => n.isPinned && n.category == 'Officielle')
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final thisWeek = events
        .where((e) => e.startDate.isBefore(weekAhead))
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    final featured = thisWeek.firstOrNull ?? events.firstOrNull;
    final registered = user != null &&
        (featured?.registeredUserIds.contains(user.id) ?? false);
    final skills = user?.skills ?? const <String>[];
    final recommended = jobs.recommendedFor(skills);
    final recommendedIds = {for (final o in recommended) o.id};
    final forYou =
        (recommended.isNotEmpty ? recommended : jobs.offers).take(5).toList();
    final completion =
        user == null ? null : _Completion.of(user, auth.emailVerified);
    final activity = user == null
        ? const <ChartPoint>[]
        : weeklyActivity(
            userId: user.id,
            articles: articles,
            notices: notices,
            events: context.watch<EventProvider>().all,
            applications: jobs.myApplications,
            now: now,
          );

    final slides = <_Slide>[
      for (final n in officials)
        _Slide(
          chipLabel: 'Officiel',
          title: n.title,
          meta: [
            FeaturedMeta(Icons.person_rounded, n.authorName),
            FeaturedMeta(Icons.schedule_rounded, _relative(n.createdAt)),
          ],
          action: 'Lire',
          onAction: () => _go(HomeTabs.notices),
        ),
      if (featured != null)
        _Slide(
          chipLabel: featured.category,
          title: featured.title,
          meta: [
            FeaturedMeta(Icons.event_rounded,
                '${featured.startDate.day} ${FrDates.months[featured.startDate.month - 1]}'),
            if (featured.location.trim().isNotEmpty)
              FeaturedMeta(Icons.place_rounded, featured.location),
          ],
          action: registered ? 'Inscrit' : 'S\'inscrire',
          onAction: registered || user == null
              ? null
              : () => _register(featured, user.id),
        ),
    ];

    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, c) {
          final columns = c.maxWidth < kCompactBreakpoint ? 2 : 3;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                kPagePadding, 16, kPagePadding, kSectionGap),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(
                      user: user,
                      greeting: _greeting(now),
                      unread: newNotices,
                      onBell: () => _go(HomeTabs.notices),
                      onAvatar: _openProfile,
                    ),
                    const SizedBox(height: 12),
                    _DateLine(
                        now: now,
                        online: connectivity.isOnline,
                        pending: connectivity.pendingActionsCount),
                    const SizedBox(height: 16),
                    SearchPill(
                        hint: 'Annonces, objets, stages',
                        onTap: _search,
                        onFilter: _search),
                    if (slides.isNotEmpty) ...[
                      const SizedBox(height: kSectionGap),
                      _Featured(
                          slides: slides,
                          onOpen: (i) => _go(i < officials.length
                              ? HomeTabs.notices
                              : HomeTabs.events)),
                    ],
                    const SizedBox(height: kSectionGap),
                    const _SectionTitle(title: 'Modules'),
                    const SizedBox(height: kHeaderGap),
                    _Modules(
                      objects: articles.length,
                      newNotices: newNotices,
                      thisWeek: thisWeek.length,
                      offers: jobs.offers.length,
                      onTap: _go,
                    ),
                    if (completion != null && completion.percent < 100) ...[
                      const SizedBox(height: kSectionGap),
                      _CompletionCard(
                          completion: completion, onComplete: _openProfile),
                    ],
                    const SizedBox(height: kSectionGap),
                    _SectionTitle(
                        title: 'Cette semaine',
                        action: 'Agenda',
                        onAction: () => _go(HomeTabs.events)),
                    const SizedBox(height: kHeaderGap),
                    if (featured == null)
                      const _EmptyLine(
                          'Aucun événement à venir pour l\'instant.')
                    else
                      _EventCard(
                        event: featured,
                        registered: registered,
                        onTap: () => _go(HomeTabs.events),
                        onRegister: user == null
                            ? null
                            : () => _register(featured, user.id),
                      ),
                    const SizedBox(height: kSectionGap),
                    _SectionTitle(
                      title: 'Stages pour toi',
                      action: 'Tout voir (${jobs.offers.length})',
                      onAction: () => _go(HomeTabs.jobs),
                    ),
                    const SizedBox(height: kHeaderGap),
                    if (forYou.isEmpty)
                      const _EmptyLine('Aucune offre publiée pour l\'instant.')
                    else
                      SizedBox(
                        height: _cardHeight(context, extra: 40),
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.none,
                          itemCount: forYou.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: kCardGap),
                          itemBuilder: (_, i) => _JobCard(
                            offer: forYou[i],
                            matchPercent: recommendedIds.contains(forYou[i].id)
                                ? (forYou[i].matchScore(skills) * 100).round()
                                : null,
                            isNew: forYou[i].postedAt.isAfter(weekAgo),
                            onTap: () => _go(HomeTabs.jobs),
                          ),
                        ),
                      ),
                    const SizedBox(height: kSectionGap),
                    _SectionTitle(
                      title: 'Vente & Don',
                      action: 'Tout voir (${articles.length})',
                      onAction: () => _go(HomeTabs.market),
                    ),
                    const SizedBox(height: kHeaderGap),
                    if (articles.isEmpty)
                      const _EmptyLine('Aucun objet proposé pour l\'instant.')
                    else
                      _ArticleGrid(
                          articles: articles.take(columns * 2).toList(),
                          columns: columns,
                          width: (c.maxWidth - 2 * kPagePadding)
                              .clamp(0, kContentMaxWidth),
                          onTap: () => _go(HomeTabs.market)),
                    const SizedBox(height: kSectionGap),
                    const _SectionTitle(title: 'Mon activité, 7 jours'),
                    const SizedBox(height: kHeaderGap),
                    _ActivityCard(points: activity),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  static String _greeting(DateTime now) {
    final h = now.hour;
    if (h < 5) return 'Bonne nuit,';
    if (h < 12) return 'Bonjour,';
    if (h < 18) return 'Bon après-midi,';
    return 'Bonsoir,';
  }

  String _relative(DateTime d) {
    final diff = _now.difference(d);
    if (diff.inMinutes < 1) return 'à l\'instant';
    if (diff.inHours < 1) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
    if (diff.inDays == 1) return 'hier';
    if (diff.inDays < 7) return 'il y a ${diff.inDays} jours';
    return 'le ${d.day} ${FrDates.months[d.month - 1]}';
  }
}

/// Complétion du profil : six éléments, un pourcentage et la liste de ce qui manque.
class _Completion {
  final int percent;
  final List<String> missing;
  const _Completion(this.percent, this.missing);

  static _Completion of(AppUser u, bool emailVerified) {
    final checks = <(String, bool)>[
      ('ta photo', u.photoUrl != null),
      ('ta filière', (u.major ?? '').isNotEmpty),
      ('ton année', (u.year ?? '').isNotEmpty),
      ('tes compétences', u.skills.isNotEmpty),
      ('ton email vérifié', emailVerified),
      ('ton téléphone', u.isPhoneVerified),
    ];
    final done = checks.where((c) => c.$2).length;
    return _Completion((done * 100 / checks.length).round(), [
      for (final c in checks)
        if (!c.$2) c.$1
    ]);
  }

  String get hint {
    if (missing.isEmpty) return 'Profil complet.';
    final shown = missing.take(2).toList();
    final list =
        shown.length == 1 ? shown.first : '${shown.first} et ${shown.last}';
    return 'Ajoute $list pour être visible des recruteurs.';
  }
}

// --- En-tête ------------------------------------------------------------------------

class _Header extends StatelessWidget {
  final AppUser? user;
  final String greeting;
  final int unread;
  final VoidCallback onBell;
  final VoidCallback onAvatar;
  const _Header(
      {required this.user,
      required this.greeting,
      required this.unread,
      required this.onBell,
      required this.onAvatar});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final firstName =
        (user?.fullName ?? 'Étudiant').trim().split(RegExp(r'\s+')).first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InitialsAvatar(
              initials: user?.initials ?? '?',
              photoUrl: user?.photoUrl,
              size: 42,
              verified: user?.isVerifiedStudent ?? false,
              onTap: onAvatar,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Campus', style: text.labelMedium),
                  Row(
                    children: [
                      Icon(Icons.location_on_rounded,
                          size: 18, color: t.primary),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text('ESPRIT Ghazela',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium),
                      ),
                      Icon(Icons.expand_more_rounded,
                          size: 20, color: t.textSecondary),
                    ],
                  ),
                ],
              ),
            ),
            RoundIconButton(
              icon: Icons.notifications_rounded,
              tooltip: 'Notifications',
              showDot: unread > 0,
              onPressed: onBell,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(greeting, style: text.bodyMedium),
        Text(firstName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.headlineLarge),
      ],
    );
  }
}

class _DateLine extends StatelessWidget {
  final DateTime now;
  final bool online;
  final int pending;
  const _DateLine(
      {required this.now, required this.online, required this.pending});

  @override
  Widget build(BuildContext context) {
    final date =
        '${FrDates.days[now.weekday - 1]} ${now.day} ${FrDates.months[now.month - 1]}';
    return Row(
      children: [
        Expanded(
            child: Text(date, style: Theme.of(context).textTheme.bodyMedium)),
        SyncChip(online: online, pending: pending),
      ],
    );
  }
}

// --- À la une ---------------------------------------------------------------------------

class _Slide {
  final String chipLabel;
  final String title;
  final List<FeaturedMeta> meta;
  final String action;

  /// Null: the action is shown disabled (already registered).
  final VoidCallback? onAction;
  const _Slide(
      {required this.chipLabel,
      required this.title,
      required this.meta,
      required this.action,
      this.onAction});
}

/// « À la une » : annonces officielles épinglées puis événement à l'affiche,
/// en pages avec des points d'indication.
class _Featured extends StatefulWidget {
  final List<_Slide> slides;

  /// Ouvre l'onglet de la page [i] (annonces ou événements).
  final ValueChanged<int> onOpen;
  const _Featured({required this.slides, required this.onOpen});

  @override
  State<_Featured> createState() => _FeaturedState();
}

class _FeaturedState extends State<_Featured> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final height = MediaQuery.textScalerOf(context).scale(170);
    final page = _page.clamp(0, widget.slides.length - 1);
    return Column(
      children: [
        SizedBox(
          height: height,
          child: PageView.builder(
            itemCount: widget.slides.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) {
              final s = widget.slides[i];
              return FeaturedCard(
                chipLabel: s.chipLabel,
                title: s.title,
                meta: s.meta,
                actionLabel: s.action,
                height: height,
                onAction: s.onAction,
                onTap: () => widget.onOpen(i),
              );
            },
          ),
        ),
        if (widget.slides.length > 1) ...[
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.slides.length; i++)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i == page ? t.primary : t.outline,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

// --- Modules ------------------------------------------------------------------------------

class _Modules extends StatelessWidget {
  final int objects;
  final int newNotices;
  final int thisWeek;
  final int offers;
  final ValueChanged<int> onTap;
  const _Modules(
      {required this.objects,
      required this.newNotices,
      required this.thisWeek,
      required this.offers,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    String n(int v, String one, String many) => '$v ${v == 1 ? one : many}';
    final modules = [
      (
        Icons.storefront_rounded,
        'Vente & Don',
        n(objects, 'objet', 'objets'),
        false,
        HomeTabs.market
      ),
      (
        Icons.campaign_rounded,
        'Annonces',
        newNotices == 0
            ? 'Aucune nouvelle'
            : n(newNotices, 'nouvelle', 'nouvelles'),
        newNotices > 0,
        HomeTabs.notices
      ),
      (
        Icons.event_rounded,
        'Événements',
        '$thisWeek cette sem.',
        false,
        HomeTabs.events
      ),
      (
        Icons.work_rounded,
        'Stages',
        n(offers, 'offre', 'offres'),
        false,
        HomeTabs.jobs
      ),
    ];
    return Wrap(
      spacing: kCardGap,
      runSpacing: 4,
      children: [
        for (final (icon, label, caption, highlight, tab) in modules)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilterChipPill(
                  selected: false,
                  icon: icon,
                  label: label,
                  onTap: () => onTap(tab)),
              const SizedBox(width: 6),
              Flexible(
                child: StatusChip(
                    label: caption,
                    style: highlight
                        ? StatusChipStyle.danger
                        : StatusChipStyle.neutral),
              ),
            ],
          ),
      ],
    );
  }
}

// --- Cartes ---------------------------------------------------------------------------------

/// Carte de surface de l'accueil (ombre en clair, filet en sombre).
class _SurfaceCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _SurfaceCard({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(20),
        border: dark ? Border.all(color: t.outline) : null,
        boxShadow: dark ? null : t.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );
  }
}

class _CompletionCard extends StatelessWidget {
  final _Completion completion;
  final VoidCallback onComplete;
  const _CompletionCard({required this.completion, required this.onComplete});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final percent = completion.percent.toDouble();
    return _SurfaceCard(
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: DonutChart(
              size: 52,
              showLegend: false,
              centerLabel: '${completion.percent} %',
              slices: [
                ChartSlice(label: 'Complété', value: percent, color: t.primary),
                ChartSlice(
                    label: 'Restant',
                    value: 100 - percent,
                    color: t.surfaceMuted),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Complète ton profil', style: text.titleMedium),
                const SizedBox(height: 3),
                Text(completion.hint, style: text.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 10),
          PillButton(label: 'Compléter', expand: false, onPressed: onComplete),
        ],
      ),
    );
  }
}

// --- Sections ---------------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const _SectionTitle({required this.title, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Row(
      children: [
        Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        if (action != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: t.primary,
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(action!),
          ),
      ],
    );
  }
}

class _EmptyLine extends StatelessWidget {
  final String text;
  const _EmptyLine(this.text);
  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.bodyMedium);
}

class _EventCard extends StatelessWidget {
  final EventModel event;
  final bool registered;
  final VoidCallback onTap;
  final VoidCallback? onRegister;
  const _EventCard(
      {required this.event,
      required this.registered,
      required this.onTap,
      required this.onRegister});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final d = event.startDate;
    final count = event.registeredUserIds.length;
    return KeyedSubtree(
      key: const Key('week-card'),
      child: _SurfaceCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 64,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                      color: t.primarySoft,
                      borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    children: [
                      Text(FrDates.dayShort[d.weekday - 1],
                          style: text.labelMedium
                              ?.copyWith(color: t.onPrimarySoft)),
                      Text('${d.day}',
                          style: text.headlineMedium
                              ?.copyWith(color: t.onPrimarySoft)),
                      Text(FrDates.monthShort[d.month - 1],
                          style: text.labelMedium
                              ?.copyWith(color: t.onPrimarySoft)),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium),
                      const SizedBox(height: 6),
                      Row(children: [
                        Icon(Icons.schedule_rounded,
                            size: 14, color: t.textSecondary),
                        const SizedBox(width: 4),
                        Text(FrDates.hhmm(d), style: text.labelMedium),
                      ]),
                      if (event.location.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(children: [
                          Icon(Icons.place_rounded,
                              size: 14, color: t.textSecondary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(event.location,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.labelMedium),
                          ),
                        ]),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: Text('$count ${count == 1 ? 'inscrit' : 'inscrits'}',
                    style: text.labelMedium),
              ),
              if (registered)
                const StatusChip(
                    label: 'Inscrit',
                    style: StatusChipStyle.success,
                    icon: Icons.check_rounded)
              else
                PillButton(
                    label: 'Je participe',
                    style: PillStyle.ghost,
                    expand: false,
                    onPressed: onRegister),
            ]),
          ],
        ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  final JobOfferModel offer;
  final int? matchPercent;
  final bool isNew;
  final VoidCallback onTap;
  const _JobCard(
      {required this.offer,
      required this.matchPercent,
      required this.isNew,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final meta = [offer.companyName, offer.location]
        .where((s) => s.isNotEmpty)
        .join(' · ');
    return PhotoCard(
      width: _railCardWidth,
      imageHeight: _cardImageHeight,
      placeholderIcon: Icons.work_rounded,
      chip: matchPercent == null
          ? null
          : StatusChip(label: '$matchPercent % match'),
      title: offer.title,
      meta: Text(meta,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium),
      footer: isNew
          ? const Align(
              alignment: Alignment.centerLeft,
              child:
                  StatusChip(label: 'Nouveau', style: StatusChipStyle.success))
          : null,
      onTap: onTap,
    );
  }
}

class _ArticleGrid extends StatelessWidget {
  final List<ArticleModel> articles;
  final int columns;
  final double width;
  final VoidCallback onTap;
  const _ArticleGrid(
      {required this.articles,
      required this.columns,
      required this.width,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cell = (width - (columns - 1) * kCardGap) / columns;
    return GridView.count(
      crossAxisCount: columns,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: kCardGap,
      crossAxisSpacing: kCardGap,
      childAspectRatio: cell / _cardHeight(context),
      children: [
        for (final a in articles) _ArticleCard(article: a, onTap: onTap),
      ],
    );
  }
}

class _ArticleCard extends StatelessWidget {
  final ArticleModel article;
  final VoidCallback onTap;
  const _ArticleCard({required this.article, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final free = article.isFree;
    return PhotoCard(
      imageHeight: _cardImageHeight,
      imageUrl: article.imageUrls.isEmpty ? null : article.imageUrls.first,
      placeholderIcon: Icons.shopping_bag_outlined,
      chip: StatusChip(
        label: free ? 'Don' : 'Vente',
        style: free ? StatusChipStyle.success : StatusChipStyle.soft,
      ),
      title: article.title,
      meta: Text(
        free ? 'Gratuit' : '${article.price!.toStringAsFixed(0)} DT',
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: free ? t.success : t.primary),
      ),
      onTap: onTap,
    );
  }
}

// --- Activité -------------------------------------------------------------------------------

class _ActivityCard extends StatelessWidget {
  final List<ChartPoint> points;
  const _ActivityCard({required this.points});

  @override
  Widget build(BuildContext context) {
    final empty = points.every((p) => p.value == 0);
    return _SurfaceCard(
      child: AreaLineChart(
        points: empty ? const [] : points,
        emptyText: 'Aucune activité cette semaine',
        tooltip: (p) => '${p.value.round()}',
      ),
    );
  }
}

// --- Recherche transversale ---------------------------------------------------------

/// Cherche dans tout ce qui est déjà chargé (objets, annonces, événements,
/// offres) ; choisir un résultat ouvre l'onglet de sa gestion.
class _CampusSearch extends SearchDelegate<int?> {
  _CampusSearch() : super(searchFieldLabel: 'Annonces, objets, stages…');

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => query = ''),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () => close(context, null));

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    final q = query.trim().toLowerCase();
    if (q.length < 2) {
      return Center(
          child: Text('Tape au moins deux lettres.',
              style: Theme.of(context).textTheme.bodyMedium));
    }
    bool hit(String s) => s.toLowerCase().contains(q);
    final hits = <(IconData, Color, String, String, int)>[
      for (final a in context.read<ArticleProvider>().items)
        if (hit(a.title) || hit(a.category))
          (
            Icons.storefront_outlined,
            ModuleColors.marketInk,
            a.title,
            a.isFree ? 'Gratuit' : '${a.price!.toStringAsFixed(0)} DT',
            HomeTabs.market
          ),
      for (final n in context.read<AnnonceProvider>().items)
        if (hit(n.title) || hit(n.content))
          (
            Icons.campaign_outlined,
            ModuleColors.noticesInk,
            n.title,
            n.category,
            HomeTabs.notices
          ),
      for (final e in context.read<EventProvider>().upcoming)
        if (hit(e.title) || hit(e.location))
          (
            Icons.event_outlined,
            ModuleColors.eventsInk,
            e.title,
            e.location,
            HomeTabs.events
          ),
      for (final j in context.read<JobProvider>().offers)
        if (hit(j.title) || hit(j.companyName))
          (
            Icons.work_outline_rounded,
            ModuleColors.jobsInk,
            j.title,
            j.companyName,
            HomeTabs.jobs
          ),
    ];
    if (hits.isEmpty) {
      return Center(
          child: Text('Aucun résultat pour « $query ».',
              style: Theme.of(context).textTheme.bodyMedium));
    }
    return ListView.builder(
      itemCount: hits.length,
      itemBuilder: (context, i) {
        final (icon, color, title, sub, tab) = hits[i];
        return ListTile(
          leading: Icon(icon, color: color),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(sub),
          onTap: () => close(context, tab),
        );
      },
    );
  }
}
