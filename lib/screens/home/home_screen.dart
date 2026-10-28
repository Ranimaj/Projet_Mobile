import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/module_colors.dart';
import '../../models/annonce_model.dart';
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
import '../profile/profile_screen.dart';

/// Onglets de [AppShell], dans l'ordre de la barre de navigation.
abstract final class HomeTabs {
  static const int home = 0;
  static const int market = 1;
  static const int notices = 2;
  static const int events = 3;
  static const int jobs = 4;
}

/// Hub central après connexion — BF13, d'après la maquette « CampusConnect
/// Home » : salutation, cloche et avatar ; date et état de synchronisation ;
/// recherche ; annonce officielle épinglée ; accès rapide aux gestions ;
/// complétion du profil ; événement de la semaine ; stages recommandés ;
/// derniers objets. Tout est calculé à partir des vraies données.
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

  void _openProfile() => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const ProfileScreen()));

  Future<void> _search() async {
    final tab =
        await showSearch<int?>(context: context, delegate: _CampusSearch());
    if (tab != null) _go(tab);
  }

  @override
  Widget build(BuildContext context) {
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
    final official =
        (notices.where((n) => n.isPinned && n.category == 'Officielle').toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt)))
            .firstOrNull;
    final thisWeek = events
        .where((e) => e.startDate.isBefore(weekAhead))
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    final featured = thisWeek.firstOrNull ?? events.firstOrNull;
    final recommended = jobs.recommendedFor(user?.skills ?? const []);
    final forYou =
        (recommended.isNotEmpty ? recommended : jobs.offers).take(5).toList();
    final completion =
        user == null ? null : _Completion.of(user, auth.emailVerified);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.fromLTRB(kPagePadding, 16, kPagePadding, 28),
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
              const SizedBox(height: 10),
              _DateLine(
                  now: now,
                  online: connectivity.isOnline,
                  pending: connectivity.pendingActionsCount),
              const SizedBox(height: 16),
              _SearchField(onTap: _search),
              if (official != null) ...[
                const SizedBox(height: 16),
                _OfficialCard(
                    notice: official,
                    when: _relative(official.createdAt),
                    onTap: () => _go(HomeTabs.notices)),
              ],
              const SizedBox(height: 16),
              _QuickAccess(
                objects: articles.length,
                newNotices: newNotices,
                thisWeek: thisWeek.length,
                offers: jobs.offers.length,
                onTap: _go,
              ),
              if (completion != null && completion.percent < 100) ...[
                const SizedBox(height: 16),
                _CompletionCard(
                    completion: completion, onComplete: _openProfile),
              ],
              const SizedBox(height: 22),
              _SectionTitle(
                  title: 'Cette semaine',
                  action: 'Agenda',
                  onAction: () => _go(HomeTabs.events)),
              const SizedBox(height: kHeaderGap),
              if (featured == null)
                const _EmptyLine('Aucun événement à venir pour l\'instant.')
              else
                _EventCard(
                  event: featured,
                  registered: user != null &&
                      featured.registeredUserIds.contains(user.id),
                  onTap: () => _go(HomeTabs.events),
                ),
              const SizedBox(height: 22),
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
                  height: 148,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    itemCount: forYou.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, i) => _JobCard(
                      offer: forYou[i],
                      isNew: forYou[i].postedAt.isAfter(weekAgo),
                      onTap: () => _go(HomeTabs.jobs),
                    ),
                  ),
                ),
              const SizedBox(height: 22),
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
                    articles: articles.take(4).toList(),
                    onTap: () => _go(HomeTabs.market)),
            ],
          ),
        ),
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
    return 'le ${d.day} ${_Fr.months[d.month - 1]}';
  }
}

abstract final class _Fr {
  static const days = [
    'Lundi',
    'Mardi',
    'Mercredi',
    'Jeudi',
    'Vendredi',
    'Samedi',
    'Dimanche'
  ];
  static const dayShort = ['LUN', 'MAR', 'MER', 'JEU', 'VEN', 'SAM', 'DIM'];
  static const months = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre'
  ];
  static const monthShort = [
    'JAN',
    'FÉV',
    'MAR',
    'AVR',
    'MAI',
    'JUIN',
    'JUIL',
    'AOÛ',
    'SEP',
    'OCT',
    'NOV',
    'DÉC'
  ];
  static String hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
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
    final text = Theme.of(context).textTheme;
    final firstName =
        (user?.fullName ?? 'Étudiant').trim().split(RegExp(r'\s+')).first;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(greeting,
                  style: text.bodyMedium?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.homeMuted)),
              Text(
                firstName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.displayLarge?.copyWith(
                    fontSize: 28,
                    height: 34 / 28,
                    letterSpacing: -0.56,
                    color: AppColors.homeInk),
              ),
            ],
          ),
        ),
        Semantics(
          button: true,
          label: unread == 0 ? 'Annonces' : 'Annonces, $unread nouvelles',
          child: Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppColors.homeBorder),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onBell,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.notifications_none_rounded,
                        size: 22, color: AppColors.homeInk),
                    if (unread > 0)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          key: const Key('bell-badge'),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.homeDanger,
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: AppColors.surface, width: 2),
                          ),
                          child: Text('$unread',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  height: 1)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          label: 'Mon profil',
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onAvatar,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.homePrimarySoft,
                border: Border.all(
                    color: AppColors.homePrimary.withValues(alpha: 0.35),
                    width: 2),
              ),
              alignment: Alignment.center,
              child: Text(user?.initials ?? '?',
                  style: const TextStyle(
                      color: AppColors.homePrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800)),
            ),
          ),
        ),
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
        '${_Fr.days[now.weekday - 1]} ${now.day} ${_Fr.months[now.month - 1]}';
    final (label, bg, fg, dot) = online
        ? (
            pending == 0 ? 'À jour' : 'Synchronisation · $pending en attente',
            AppColors.homeSuccessSoft,
            AppColors.homeSuccessInk,
            AppColors.homeSuccessDot
          )
        : (
            'Hors-ligne · $pending en attente',
            AppColors.homeWarnSoft,
            AppColors.homeWarnInk,
            AppColors.homeWarnInk
          );
    return Row(
      children: [
        Expanded(
            child: Text(date,
                style:
                    const TextStyle(fontSize: 13, color: AppColors.homeMuted))),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(999)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 6,
                  height: 6,
                  decoration:
                      BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  final VoidCallback onTap;
  const _SearchField({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.homeBorder)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const SizedBox(
          height: 52,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Icon(Icons.search_rounded, size: 20, color: AppColors.homeMuted),
              SizedBox(width: 12),
              Expanded(
                child: Text('Annonces, objets, stages…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: AppColors.homeHint)),
              ),
              Icon(Icons.tune_rounded, size: 20, color: AppColors.homeMuted),
            ]),
          ),
        ),
      ),
    );
  }
}

class _OfficialCard extends StatelessWidget {
  final AnnonceModel notice;
  final String when;
  final VoidCallback onTap;
  const _OfficialCard(
      {required this.notice, required this.when, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.homeOfficialSoft,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.homeOfficialEdge)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: AppColors.homeWarnSoft,
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.push_pin_outlined,
                    size: 18, color: AppColors.homeOfficialLabel),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Officiel · Épinglé',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.homeOfficialLabel)),
                    const SizedBox(height: 2),
                    Text(notice.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16,
                            height: 22 / 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.homeInk)),
                    const SizedBox(height: 2),
                    Text('${notice.authorName} · $when',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.homeOfficialMeta)),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Icon(Icons.chevron_right_rounded,
                    size: 20, color: AppColors.homeOfficialLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Accès rapide ------------------------------------------------------------------------

class _QuickAccess extends StatelessWidget {
  final int objects;
  final int newNotices;
  final int thisWeek;
  final int offers;
  final ValueChanged<int> onTap;
  const _QuickAccess(
      {required this.objects,
      required this.newNotices,
      required this.thisWeek,
      required this.offers,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    String n(int v, String one, String many) => '$v ${v == 1 ? one : many}';
    final tiles = [
      _Tile(
          Icons.storefront_outlined,
          'Vente & Don',
          n(objects, 'objet', 'objets'),
          ModuleColors.marketInk,
          ModuleColors.marketSoft,
          HomeTabs.market),
      _Tile(
          Icons.campaign_outlined,
          'Annonces',
          newNotices == 0
              ? 'Aucune nouvelle'
              : n(newNotices, 'nouvelle', 'nouvelles'),
          ModuleColors.noticesInk,
          ModuleColors.noticesSoft,
          HomeTabs.notices,
          captionColor: newNotices == 0 ? null : AppColors.homeDanger),
      _Tile(
          Icons.event_outlined,
          'Événements',
          n(thisWeek, 'cette sem.', 'cette sem.'),
          ModuleColors.eventsInk,
          ModuleColors.eventsSoft,
          HomeTabs.events),
      _Tile(Icons.work_outline_rounded, 'Stages', n(offers, 'offre', 'offres'),
          ModuleColors.jobsInk, ModuleColors.jobsSoft, HomeTabs.jobs),
    ];
    // IntrinsicHeight : les quatre tuiles ont la même hauteur.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
                child: _QuickTile(
                    tile: tiles[i], onTap: () => onTap(tiles[i].tab))),
          ],
        ],
      ),
    );
  }
}

class _Tile {
  final IconData icon;
  final String label;
  final String caption;
  final Color ink;
  final Color soft;
  final int tab;
  final Color? captionColor;
  const _Tile(
      this.icon, this.label, this.caption, this.ink, this.soft, this.tab,
      {this.captionColor});
}

class _QuickTile extends StatelessWidget {
  final _Tile tile;
  final VoidCallback onTap;
  const _QuickTile({required this.tile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.homeBorder)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 12),
          child: Column(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    color: tile.soft, borderRadius: BorderRadius.circular(14)),
                child: Icon(tile.icon, size: 22, color: tile.ink),
              ),
              const SizedBox(height: 8),
              // Une ligne qui se réduit au besoin : pas de coupure au milieu d'un mot.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(tile.label,
                    maxLines: 1,
                    style: const TextStyle(
                        fontSize: 13,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: AppColors.homeInk)),
              ),
              const SizedBox(height: 2),
              Text(tile.caption,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: tile.captionColor == null
                        ? FontWeight.w400
                        : FontWeight.w600,
                    color: tile.captionColor ?? AppColors.homeMuted,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Complétion du profil -----------------------------------------------------------------

class _CompletionCard extends StatelessWidget {
  final _Completion completion;
  final VoidCallback onComplete;
  const _CompletionCard({required this.completion, required this.onComplete});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.homeBorder),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: completion.percent / 100,
                  strokeWidth: 5,
                  strokeCap: StrokeCap.round,
                  backgroundColor: AppColors.homePrimarySoft,
                  color: AppColors.homePrimary,
                ),
                Center(
                  child: Text('${completion.percent}%',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.homeInk)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Complète ton profil',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.homeInk)),
                const SizedBox(height: 3),
                Text(completion.hint,
                    style: const TextStyle(
                        fontSize: 13,
                        height: 18 / 13,
                        color: AppColors.homeMuted)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: onComplete,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.homePrimary,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            child: const Text('Compléter'),
          ),
        ],
      ),
    );
  }
}

// --- Sections ---------------------------------------------------------------------------------

class _SectionTitle extends StatelessWidget {
  final String title;
  final String action;
  final VoidCallback onAction;
  const _SectionTitle(
      {required this.title, required this.action, required this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 18,
                  letterSpacing: -0.18,
                  color: AppColors.homeInk)),
        ),
        TextButton(
          onPressed: onAction,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.homePrimary,
            minimumSize: const Size(48, 40),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            textStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          child: Text(action),
        ),
      ],
    );
  }
}

class _EmptyLine extends StatelessWidget {
  final String text;
  const _EmptyLine(this.text);
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          fontSize: 14, color: AppColors.homeMuted, height: 1.4));
}

class _EventCard extends StatelessWidget {
  final EventModel event;
  final bool registered;
  final VoidCallback onTap;
  const _EventCard(
      {required this.event, required this.registered, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final d = event.startDate;
    final count = event.registeredUserIds.length;
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.homeBorder)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 60,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                    color: ModuleColors.eventsSoft,
                    borderRadius: BorderRadius.circular(14)),
                child: Column(
                  children: [
                    Text(_Fr.dayShort[d.weekday - 1],
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: ModuleColors.eventsInk)),
                    Text('${d.day}',
                        style: const TextStyle(
                            fontSize: 24,
                            height: 28 / 24,
                            fontWeight: FontWeight.w800,
                            color: AppColors.homeInk)),
                    Text(_Fr.monthShort[d.month - 1],
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: ModuleColors.eventsInk)),
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
                        style: const TextStyle(
                            fontSize: 15,
                            height: 20 / 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.homeInk)),
                    const SizedBox(height: 6),
                    Row(children: [
                      const Icon(Icons.schedule_rounded,
                          size: 14, color: AppColors.homeMuted),
                      const SizedBox(width: 4),
                      Text(_Fr.hhmm(d),
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.homeMuted)),
                      if (event.location.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.place_outlined,
                            size: 14, color: AppColors.homeMuted),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(event.location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13, color: AppColors.homeMuted)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: Text(
                            '$count ${count == 1 ? 'inscrit' : 'inscrits'}',
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.homeMuted)),
                      ),
                      OutlinedButton(
                        onPressed: onTap,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: registered
                              ? AppColors.homeSuccessInk
                              : AppColors.homePrimary,
                          backgroundColor: registered
                              ? AppColors.homeSuccessSoft
                              : AppColors.surface,
                          side: BorderSide(
                              color: registered
                                  ? AppColors.homeSuccessSoft
                                  : AppColors.homePrimary
                                      .withValues(alpha: 0.5)),
                          minimumSize: const Size(0, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          textStyle: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        child: Text(registered ? 'Inscrit' : 'Je participe'),
                      ),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  final JobOfferModel offer;
  final bool isNew;
  final VoidCallback onTap;
  const _JobCard(
      {required this.offer, required this.isNew, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final initial =
        offer.companyName.isNotEmpty ? offer.companyName[0].toUpperCase() : '?';
    final type = offer.type == JobType.stage ? 'Stage' : 'Emploi';
    final meta = [offer.companyName, offer.location, type]
        .where((s) => s.isNotEmpty)
        .join(' · ');
    return SizedBox(
      width: 220,
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppColors.homeBorder)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isNew
                            ? AppColors.homeInk
                            : AppColors.homePrimarySoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(initial,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: isNew
                                  ? Colors.white
                                  : AppColors.homePrimary)),
                    ),
                    if (isNew)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: AppColors.homeSuccessSoft,
                            borderRadius: BorderRadius.circular(999)),
                        child: const Text('Nouveau',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.homeSuccessInk)),
                      ),
                  ],
                ),
                const Spacer(),
                Text(offer.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15,
                        height: 20 / 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.homeInk)),
                const SizedBox(height: 4),
                Text(meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.homeMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArticleGrid extends StatelessWidget {
  final List<ArticleModel> articles;
  final VoidCallback onTap;
  const _ArticleGrid({required this.articles, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var row = 0; row < articles.length; row += 2) ...[
          if (row > 0) const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                    child: _ArticleCard(
                        article: articles[row], index: row, onTap: onTap)),
                const SizedBox(width: 12),
                Expanded(
                  child: row + 1 < articles.length
                      ? _ArticleCard(
                          article: articles[row + 1],
                          index: row + 1,
                          onTap: onTap)
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ArticleCard extends StatelessWidget {
  final ArticleModel article;
  final int index;
  final VoidCallback onTap;
  const _ArticleCard(
      {required this.article, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final free = article.isFree;
    final soft = free
        ? AppColors.homeSuccessSoft
        : (index.isEven ? ModuleColors.marketSoft : ModuleColors.eventsSoft);
    final ink = free
        ? AppColors.homeSuccessInk
        : (index.isEven ? ModuleColors.marketInk : ModuleColors.eventsInk);
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.homeBorder)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Container(
                  height: 112,
                  width: double.infinity,
                  color: soft,
                  child: Icon(Icons.image_outlined,
                      size: 36, color: ink.withValues(alpha: 0.7)),
                ),
                Positioned(
                  left: 10,
                  top: 10,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(999)),
                    child: Text(free ? 'Don' : 'Vente',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.homeInk)),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(article.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.homeInk)),
                  const SizedBox(height: 2),
                  Text(
                    free
                        ? 'Gratuit'
                        : '${article.price!.toStringAsFixed(0)} DT',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: free
                            ? AppColors.homeSuccessInk
                            : AppColors.homePrimary),
                  ),
                ],
              ),
            ),
          ],
        ),
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
