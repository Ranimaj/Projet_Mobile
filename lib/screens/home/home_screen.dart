import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/module_colors.dart';
import '../../models/annonce_model.dart';
import '../../models/event_model.dart';
import '../../models/job_offer_model.dart';
import '../../models/user_model.dart';
import '../../providers/annonce_provider.dart';
import '../../providers/article_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/event_provider.dart';
import '../../providers/job_provider.dart';
import '../../widgets/offline_banner.dart';

/// Onglets de [AppShell], dans l'ordre de la barre de navigation.
abstract final class HomeTabs {
  static const int home = 0;
  static const int market = 1;
  static const int notices = 2;
  static const int events = 3;
  static const int jobs = 4;
  static const int profile = 5;
}

/// Hub central après connexion — BF13, d'après la maquette « Home (hub
/// central) » : en-tête dégradé (salutation, avatar, recherche), bandeau
/// hors-ligne, « Mes modules » avec compteurs réels, puis « Activité
/// récente » construite à partir des vraies données de l'étudiant
/// (candidatures, événements où il est inscrit, annonces officielles).
class HomeScreen extends StatefulWidget {
  /// Bascule l'onglet de [AppShell] (les modules ne poussent pas d'écran).
  final ValueChanged<int>? onNavigate;

  /// Horloge injectable (salutation selon l'heure, dates relatives).
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

  Future<void> _search() async {
    final tab = await showSearch<int?>(
        context: context, delegate: _CampusSearch(now: _now));
    if (tab != null) _go(tab);
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    final articles = context.watch<ArticleProvider>().items;
    final notices = context.watch<AnnonceProvider>().items;
    final events = context.watch<EventProvider>().upcoming;
    final jobs = context.watch<JobProvider>();
    final text = Theme.of(context).textTheme;

    final matching = jobs.recommendedFor(user?.skills ?? const []).length;
    final weekEnd = _now.add(const Duration(days: 7));
    final thisWeek = events.where((e) => e.startDate.isBefore(weekEnd)).length;
    final urgent = notices
        .any((n) => n.isUrgent || (n.isPinned && n.category == 'Officielle'));
    final activity = _buildActivity(user, jobs.myApplications, events, notices);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _Header(
              user: user,
              greeting: _greeting(_now),
              onAvatar: () => _go(HomeTabs.profile),
              onSearch: _search),
          const OfflineBanner(),
          Expanded(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.fromLTRB(kPagePadding, 20, kPagePadding, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mes modules', style: text.titleLarge),
                  const SizedBox(height: kHeaderGap),
                  Row(children: [
                    Expanded(
                      child: _ModuleCard(
                        icon: Icons.person_rounded,
                        label: 'Mon profil',
                        accent: AppColors.primary,
                        caption: user == null ? null : _profileCaption(user),
                        onTap: () => _go(HomeTabs.profile),
                      ),
                    ),
                    const SizedBox(width: kCardGap),
                    Expanded(
                      child: _ModuleCard(
                        icon: Icons.storefront_rounded,
                        label: 'Vente & Don',
                        accent: ModuleColors.market,
                        caption: _plural(articles.length, 'objet', 'objets'),
                        onTap: () => _go(HomeTabs.market),
                      ),
                    ),
                  ]),
                  const SizedBox(height: kCardGap),
                  Row(children: [
                    Expanded(
                      child: _ModuleCard(
                        icon: Icons.campaign_rounded,
                        label: 'Annonces',
                        accent: ModuleColors.notices,
                        caption: _plural(notices.length, 'annonce', 'annonces'),
                        dot: urgent,
                        onTap: () => _go(HomeTabs.notices),
                      ),
                    ),
                    const SizedBox(width: kCardGap),
                    Expanded(
                      child: _ModuleCard(
                        icon: Icons.event_rounded,
                        label: 'Événements',
                        accent: ModuleColors.events,
                        caption: thisWeek == 0
                            ? 'Rien cette semaine'
                            : _plural(
                                thisWeek, 'cette semaine', 'cette semaine'),
                        onTap: () => _go(HomeTabs.events),
                      ),
                    ),
                  ]),
                  const SizedBox(height: kCardGap),
                  _JobsCard(
                    matching: matching,
                    total: jobs.offers.length,
                    onTap: () => _go(HomeTabs.jobs),
                  ),
                  const SizedBox(height: kSectionGap - 4),
                  Text('Activité récente', style: text.titleLarge),
                  const SizedBox(height: kHeaderGap),
                  if (activity.isEmpty)
                    _EmptyActivity(onExplore: () => _go(HomeTabs.events))
                  else
                    // Material sous les ListTile : sinon leurs encres sont invisibles.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [AppColors.cardShadow],
                      ),
                      child: Material(
                        color: AppColors.surface,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            for (final a in activity)
                              ListTile(
                                onTap: () => _go(a.tab),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 4),
                                leading: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: ModuleColors.tint(a.accent),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child:
                                      Icon(a.icon, size: 18, color: a.accent),
                                ),
                                title: Text(a.text, style: text.titleSmall),
                                subtitle: a.when == null
                                    ? null
                                    : Text(a.when!, style: text.bodyMedium),
                                trailing: const Icon(
                                    Icons.chevron_right_rounded,
                                    size: 20,
                                    color: AppColors.textSecondary),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _greeting(DateTime now) {
    final h = now.hour;
    if (h < 5) return 'Bonne nuit';
    if (h < 12) return 'Bonjour';
    if (h < 18) return 'Bon après-midi';
    return 'Bonsoir';
  }

  static String _plural(int n, String one, String many) =>
      '$n ${n == 1 ? one : many}';

  static String _profileCaption(AppUser user) {
    if (user.isVerifiedStudent) return 'Étudiant vérifié';
    final missing = <String>[
      if (user.photoUrl == null) 'photo',
      if ((user.major ?? '').isEmpty) 'filière',
      if (user.skills.isEmpty) 'compétences',
    ];
    return missing.isEmpty
        ? 'Profil complet'
        : 'À compléter : ${missing.join(', ')}';
  }

  /// Fil d'activité : dernières candidatures, prochain événement où l'étudiant
  /// est inscrit, annonce officielle épinglée. Jamais plus de cinq lignes.
  List<_Activity> _buildActivity(
    AppUser? user,
    List<ApplicationModel> applications,
    List<EventModel> events,
    List<AnnonceModel> notices,
  ) {
    final items = <_Activity>[];
    final sortedApps = [...applications]
      ..sort((a, b) => b.appliedAt.compareTo(a.appliedAt));
    for (final app in sortedApps.take(2)) {
      final verb = switch (app.status) {
        ApplicationStatus.sent => 'a été envoyée',
        ApplicationStatus.seen => 'a été vue',
        ApplicationStatus.accepted => 'a été acceptée',
        ApplicationStatus.rejected => 'n\'a pas été retenue',
      };
      final (icon, accent) = switch (app.status) {
        ApplicationStatus.accepted => (
            Icons.check_circle_rounded,
            AppColors.success
          ),
        ApplicationStatus.rejected => (Icons.cancel_rounded, AppColors.danger),
        _ => (Icons.work_rounded, ModuleColors.jobs),
      };
      items.add(_Activity(
        icon: icon,
        accent: accent,
        text: 'Votre candidature chez ${app.companyName} $verb',
        when: _relative(app.appliedAt),
        tab: HomeTabs.jobs,
      ));
    }
    if (user != null) {
      final mine = events
          .where((e) => e.registeredUserIds.contains(user.id))
          .toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));
      if (mine.isNotEmpty) {
        final e = mine.first;
        items.add(_Activity(
          icon: Icons.alarm_rounded,
          accent: ModuleColors.events,
          text: 'Rappel : ${e.title}',
          when: '${_relativeDay(e.startDate)} à ${_hhmm(e.startDate)}',
          tab: HomeTabs.events,
        ));
      }
    }
    final official = notices
        .where((n) => n.isPinned && n.category == 'Officielle')
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (official.isNotEmpty) {
      items.add(_Activity(
        icon: Icons.push_pin_rounded,
        accent: ModuleColors.notices,
        text: official.first.title,
        when: 'Annonce officielle · ${_relative(official.first.createdAt)}',
        tab: HomeTabs.notices,
      ));
    }
    return items.take(5).toList();
  }

  String _relativeDay(DateTime d) {
    final today = DateTime(_now.year, _now.month, _now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = day.difference(today).inDays;
    if (diff == 0) return 'aujourd\'hui';
    if (diff == 1) return 'demain';
    const months = [
      'janv.',
      'févr.',
      'mars',
      'avr.',
      'mai',
      'juin',
      'juil.',
      'août',
      'sept.',
      'oct.',
      'nov.',
      'déc.'
    ];
    return 'le ${d.day} ${months[d.month - 1]}';
  }

  String _relative(DateTime d) {
    final diff = _now.difference(d);
    if (diff.inMinutes < 1) return 'à l\'instant';
    if (diff.inHours < 1) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
    if (diff.inDays == 1) return 'hier';
    if (diff.inDays < 7) return 'il y a ${diff.inDays} jours';
    return _relativeDay(d);
  }

  static String _hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}h${d.minute.toString().padLeft(2, '0')}';
}

class _Activity {
  final IconData icon;
  final Color accent;
  final String text;
  final String? when;
  final int tab;
  const _Activity(
      {required this.icon,
      required this.accent,
      required this.text,
      this.when,
      required this.tab});
}

// --- En-tête -----------------------------------------------------------------------

class _Header extends StatelessWidget {
  final AppUser? user;
  final String greeting;
  final VoidCallback onAvatar;
  final VoidCallback onSearch;
  const _Header(
      {required this.user,
      required this.greeting,
      required this.onAvatar,
      required this.onSearch});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(kPagePadding,
          MediaQuery.paddingOf(context).top + 12, kPagePadding, 20),
      decoration: const BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(greeting,
                        style: text.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.85))),
                    Text(
                      user?.fullName ?? 'Étudiant',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.headlineMedium
                          ?.copyWith(color: Colors.white, fontSize: 22),
                    ),
                  ],
                ),
              ),
              Semantics(
                button: true,
                label: 'Mon profil',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onAvatar,
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    child: Text(user?.initials ?? '?',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onSearch,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Row(children: [
                  const Icon(Icons.search_rounded,
                      size: 20, color: AppColors.textSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Rechercher sur CampusConnect…',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Modules --------------------------------------------------------------------------

class _ModuleCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final String? caption;
  final bool dot;
  final VoidCallback onTap;

  const _ModuleCard({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
    this.caption,
    this.dot = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [AppColors.cardShadow],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: ModuleColors.tint(accent),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: accent, size: 22),
                    ),
                    const Spacer(),
                    if (dot)
                      Container(
                        key: const Key('module-dot'),
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                            color: AppColors.danger, shape: BoxShape.circle),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(label, style: text.titleSmall?.copyWith(fontSize: 15)),
                if (caption != null) ...[
                  const SizedBox(height: 2),
                  Text(caption!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(fontSize: 13)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _JobsCard extends StatelessWidget {
  final int matching;
  final int total;
  final VoidCallback onTap;
  const _JobsCard(
      {required this.matching, required this.total, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final subtitle = matching > 0
        ? '$matching ${matching == 1 ? 'offre correspond' : 'offres correspondent'} à votre profil'
        : total == 0
            ? 'Aucune offre pour l\'instant'
            : '$total ${total == 1 ? 'offre disponible' : 'offres disponibles'}';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [AppColors.cardShadow],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: ModuleColors.tint(ModuleColors.jobs),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.work_rounded,
                      color: ModuleColors.jobs, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Stage & Emploi',
                          style: text.titleSmall?.copyWith(fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: text.bodyMedium?.copyWith(fontSize: 13)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyActivity extends StatelessWidget {
  final VoidCallback onExplore;
  const _EmptyActivity({required this.onExplore});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [AppColors.cardShadow],
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_rounded, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
                'Rien de nouveau pour l\'instant. Inscris-toi à un événement ou postule à une offre.',
                style: text.bodyMedium),
          ),
          TextButton(onPressed: onExplore, child: const Text('Explorer')),
        ],
      ),
    );
  }
}

// --- Recherche transversale ---------------------------------------------------------

/// Cherche dans tout ce qui est déjà chargé (objets, annonces, événements,
/// offres) ; choisir un résultat ouvre l'onglet de sa gestion.
class _CampusSearch extends SearchDelegate<int?> {
  final DateTime now;
  _CampusSearch({required this.now})
      : super(searchFieldLabel: 'Rechercher sur CampusConnect…');

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
    final hits = <_Activity>[
      for (final a in context.read<ArticleProvider>().items)
        if (hit(a.title) || hit(a.category))
          _Activity(
              icon: Icons.storefront_rounded,
              accent: ModuleColors.market,
              text: a.title,
              when: a.isFree ? 'Gratuit' : '${a.price!.toStringAsFixed(0)} DT',
              tab: HomeTabs.market),
      for (final n in context.read<AnnonceProvider>().items)
        if (hit(n.title) || hit(n.content))
          _Activity(
              icon: Icons.campaign_rounded,
              accent: ModuleColors.notices,
              text: n.title,
              when: n.category,
              tab: HomeTabs.notices),
      for (final e in context.read<EventProvider>().upcoming)
        if (hit(e.title) || hit(e.location))
          _Activity(
              icon: Icons.event_rounded,
              accent: ModuleColors.events,
              text: e.title,
              when: e.location,
              tab: HomeTabs.events),
      for (final j in context.read<JobProvider>().offers)
        if (hit(j.title) || hit(j.companyName))
          _Activity(
              icon: Icons.work_rounded,
              accent: ModuleColors.jobs,
              text: j.title,
              when: j.companyName,
              tab: HomeTabs.jobs),
    ];
    if (hits.isEmpty) {
      return Center(
          child: Text('Aucun résultat pour « $query ».',
              style: Theme.of(context).textTheme.bodyMedium));
    }
    return ListView.builder(
      itemCount: hits.length,
      itemBuilder: (context, i) {
        final h = hits[i];
        return ListTile(
          leading: Icon(h.icon, color: h.accent),
          title: Text(h.text, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: h.when == null ? null : Text(h.when!),
          onTap: () => close(context, h.tab),
        );
      },
    );
  }
}
