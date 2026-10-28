import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/layout.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/annonce_model.dart';
import '../../models/article_model.dart';
import '../../models/event_model.dart';
import '../../models/job_offer_model.dart';
import '../../providers/annonce_provider.dart';
import '../../providers/article_provider.dart';
import '../../providers/event_provider.dart';
import '../../providers/job_provider.dart';
import '../../widgets/bottom_action_bar.dart';
import '../../widgets/featured_card.dart';
import '../../widgets/photo_card.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/setting_row.dart';
import '../../widgets/skeleton_box.dart';
import '../../widgets/status_chip.dart';
import '../auth/login_screen.dart';
import '../auth/register_screen.dart';

/// Accueil Visiteur (non connecté) — BF3 : héro photo avec pastilles de
/// chiffres, puis une section par gestion (Vente & Don, Annonces, Événements,
/// Stage & Emploi) avec « Voir tout », et l'appel à l'inscription dans une barre
/// fixe en pied d'écran. Les chiffres sont réels (jamais inventés).
/// Voile sombre posé sur la photo du héro (seul littéral de couleur permis :
/// il doit rester noir quel que soit le thème pour garder le texte lisible).
const _scrimTop = Color(0x33000000);
const _scrimBottom = Color(0xCC000000);

/// Hauteur des rails de cartes (image 100 + titre sur 2 lignes + méta).
const double _railHeight = 212;
const double _cardWidth = 168;
const double _cardImageHeight = 100;

class VisitorHomeScreen extends StatefulWidget {
  /// Nombre d'étudiants inscrits (pastille du héro). Injectable dans les tests ;
  /// par défaut, comptage Firestore de la collection `users`.
  final Future<int> Function()? studentsCount;

  const VisitorHomeScreen({super.key, this.studentsCount});

  @override
  State<VisitorHomeScreen> createState() => _VisitorHomeScreenState();
}

class _VisitorHomeScreenState extends State<VisitorHomeScreen> {
  late final Future<int> _students = (widget.studentsCount ?? _countStudents)();

  static Future<int> _countStudents() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(AppConstants.usersCollection)
          .count()
          .get();
      return snap.count ?? 0;
    } catch (_) {
      return 0;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ArticleProvider>().load();
      context.read<AnnonceProvider>().load();
      context.read<EventProvider>().load();
      context.read<JobProvider>().load();
    });
  }

  void _openRegister() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const RegisterScreen()));

  void _openLogin() => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const LoginScreen()));

  @override
  Widget build(BuildContext context) {
    final articles = context.watch<ArticleProvider>();
    final annonces = context.watch<AnnonceProvider>();
    final events = context.watch<EventProvider>();
    final jobs = context.watch<JobProvider>();

    final forSale = articles.items.take(5).toList();
    final notices = annonces.publicPreview;
    final upcoming = events.publicPreview;
    final offers = jobs.offers.take(5).toList();
    final companies = jobs.offers
        .map((o) => o.companyName.trim().toLowerCase())
        .where((c) => c.isNotEmpty)
        .toSet();

    final t = AppTokens.of(context);
    final media = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: t.background,
      body: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth > kCompactBreakpoint;
        final heroHeight = (c.maxHeight * 0.36).clamp(220.0, 320.0);

        Widget sections = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: kSectionGap),
            _Section(
              title: 'Vente & Don',
              onSeeAll: _openLogin,
              child: _Rail(
                loading: articles.isLoading && forSale.isEmpty,
                emptyText: 'Aucun objet proposé pour l\'instant.',
                children: [
                  for (final a in forSale) _ArticleCard(article: a),
                ],
              ),
            ),
            const SizedBox(height: kSectionGap),
            _Section(
              title: 'Annonces du campus',
              onSeeAll: _openLogin,
              child: _Notices(
                loading: annonces.isLoading && notices.isEmpty,
                notices: notices.take(3).toList(),
                onTap: _openLogin,
              ),
            ),
            const SizedBox(height: kSectionGap),
            _Section(
              title: 'Événements à venir',
              onSeeAll: _openLogin,
              child: _Events(
                loading: events.isLoading && upcoming.isEmpty,
                events: upcoming,
                onOpen: _openLogin,
              ),
            ),
            const SizedBox(height: kSectionGap),
            _Section(
              title: 'Stage & Emploi',
              onSeeAll: _openLogin,
              child: _Rail(
                loading: jobs.isLoading && offers.isEmpty,
                emptyText: 'Aucune offre publiée pour l\'instant.',
                children: [for (final j in offers) _OfferCard(offer: j)],
              ),
            ),
            const SizedBox(height: kSectionGap),
            const _InfoBox(),
            // Clears the fixed bottom bar.
            SizedBox(height: 168 + media.padding.bottom),
          ],
        );
        if (wide) {
          sections = Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
              child: sections,
            ),
          );
        }

        return Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Hero(
                    height: heroHeight,
                    students: _students,
                    notices: annonces.items.length,
                    companies: companies.length,
                  ),
                  sections,
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: BottomActionBar(
                child: Center(
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: kContentMaxWidth),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PillButton(
                            label: 'Créer un compte étudiant',
                            onPressed: _openRegister),
                        const SizedBox(height: 8),
                        PillButton(
                            label: 'Se connecter',
                            style: PillStyle.ghost,
                            onPressed: _openLogin),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

// --- Héro --------------------------------------------------------------------------

class _Hero extends StatelessWidget {
  final double height;
  final Future<int> students;
  final int notices;
  final int companies;
  const _Hero(
      {required this.height,
      required this.students,
      required this.notices,
      required this.companies});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(kHeroBottomRadius)),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/onboarding/campus_2.jpg',
              fit: BoxFit.cover,
              cacheWidth: 1080,
              excludeFromSemantics: true,
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [_scrimBottom, _scrimTop],
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            constraints: BoxConstraints(minHeight: height),
            alignment: Alignment.bottomLeft,
            padding: EdgeInsets.fromLTRB(kPagePadding,
                MediaQuery.paddingOf(context).top + 12, kPagePadding, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CampusConnect',
                    style: text.titleLarge?.copyWith(color: t.onPrimary)),
                const SizedBox(height: 12),
                Text(
                  'Tout ton campus,\ndans une seule app',
                  style: text.displayMedium
                      ?.copyWith(color: t.onPrimary, height: 1.2),
                ),
                const SizedBox(height: 8),
                Text(
                  'Échange, informe-toi, participe aux événements et trouve ton futur stage, avec les étudiants de ton école.',
                  style: text.bodyMedium?.copyWith(color: t.onPrimary),
                ),
                const SizedBox(height: 16),
                FutureBuilder<int>(
                  future: students,
                  builder: (context, snap) {
                    final n = snap.data;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        StatusChip(
                            style: StatusChipStyle.onPhoto,
                            label:
                                '${n ?? '…'} ${n == 1 ? 'étudiant' : 'étudiants'}'),
                        StatusChip(
                            style: StatusChipStyle.onPhoto,
                            label:
                                '$notices ${notices == 1 ? 'annonce' : 'annonces'}'),
                        StatusChip(
                            style: StatusChipStyle.onPhoto,
                            label:
                                '$companies ${companies == 1 ? 'entreprise' : 'entreprises'}'),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Sections et rails -----------------------------------------------------------

class _Section extends StatelessWidget {
  final String title;
  final VoidCallback onSeeAll;
  final Widget child;
  const _Section(
      {required this.title, required this.onSeeAll, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
          child: Row(
            children: [
              Expanded(child: Text(title, style: text.titleLarge)),
              TextButton(
                onPressed: onSeeAll,
                style: TextButton.styleFrom(
                  foregroundColor: t.primary,
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Voir tout'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _EmptyText extends StatelessWidget {
  final String text;
  const _EmptyText(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: kPagePadding, vertical: 8),
        child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
      );
}

/// Horizontal rail of cards: skeletons while loading, a sober text when there
/// is nothing, the cards otherwise.
class _Rail extends StatelessWidget {
  final bool loading;
  final String emptyText;
  final List<Widget> children;

  const _Rail({
    required this.loading,
    required this.emptyText,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    if (!loading && children.isEmpty) return _EmptyText(emptyText);
    final items = loading
        ? List<Widget>.filled(
            3,
            const SkeletonBox(
                width: _cardWidth, height: _railHeight, radius: 20))
        : children;
    return SizedBox(
      height: _railHeight + 16,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(kPagePadding, 8, kPagePadding, 8),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: kCardGap),
        itemBuilder: (context, i) => items[i],
      ),
    );
  }
}

// --- Cartes ---------------------------------------------------------------------------

class _ArticleCard extends StatelessWidget {
  final ArticleModel article;
  const _ArticleCard({required this.article});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final free = article.isFree;
    return PhotoCard(
      width: _cardWidth,
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
        style: text.titleSmall?.copyWith(color: free ? t.success : t.primary),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  final JobOfferModel offer;
  const _OfferCard({required this.offer});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return PhotoCard(
      width: _cardWidth,
      imageHeight: _cardImageHeight,
      placeholderIcon: Icons.work_rounded,
      chip: StatusChip(label: offer.type == JobType.stage ? 'Stage' : 'Emploi'),
      title: offer.title,
      meta: Text('${offer.companyName} · ${offer.location}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.labelMedium),
    );
  }
}

class _Events extends StatelessWidget {
  final bool loading;
  final List<EventModel> events;
  final VoidCallback onOpen;
  const _Events(
      {required this.loading, required this.events, required this.onOpen});

  static const _months = [
    'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', //
    'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'
  ];

  static String _date(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: kPagePadding, vertical: 8),
        child: SkeletonBox(height: 170, radius: 24),
      );
    }
    if (events.isEmpty) {
      return const _EmptyText('Aucun événement annoncé pour l\'instant.');
    }
    final first = events.first;
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: kPagePadding, vertical: 8),
          child: FeaturedCard(
            chipLabel: first.category,
            title: first.title,
            meta: [
              FeaturedMeta(Icons.event_rounded, _date(first.startDate)),
              FeaturedMeta(Icons.place_rounded, first.location),
            ],
            actionLabel: 'Voir',
            onAction: onOpen,
            onTap: onOpen,
          ),
        ),
        if (events.length > 1)
          _Rail(
            loading: false,
            emptyText: '',
            children: [
              for (final e in events.skip(1))
                PhotoCard(
                  width: _cardWidth,
                  imageHeight: _cardImageHeight,
                  placeholderIcon: Icons.event_rounded,
                  chip: StatusChip(label: e.category),
                  title: e.title,
                  meta: Text('${_date(e.startDate)} · ${e.location}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelMedium),
                  onTap: onOpen,
                ),
            ],
          ),
      ],
    );
  }
}

class _Notices extends StatelessWidget {
  final bool loading;
  final List<AnnonceModel> notices;
  final VoidCallback onTap;
  const _Notices(
      {required this.loading, required this.notices, required this.onTap});

  static IconData _icon(AnnonceModel n) {
    if (n.isPinned) return Icons.push_pin_rounded;
    return switch (n.category) {
      'Officielle' => Icons.verified_rounded,
      'Perdu & Trouvé' => Icons.search_rounded,
      _ => Icons.campaign_rounded,
    };
  }

  static String _ago(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays >= 30) return 'il y a ${diff.inDays ~/ 30} mois';
    if (diff.inDays >= 1) return 'il y a ${diff.inDays} j';
    if (diff.inHours >= 1) return 'il y a ${diff.inHours} h';
    return 'à l\'instant';
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: kPagePadding, vertical: 8),
        child: SkeletonBox(height: 168, radius: 16),
      );
    }
    if (notices.isEmpty) {
      return const _EmptyText('Aucune annonce publiée pour l\'instant.');
    }
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: kPagePadding, vertical: 8),
      child: SettingGroup(
        children: [
          for (final n in notices)
            SettingRow(
              icon: _icon(n),
              title: n.title,
              subtitle: '${n.authorName} · ${_ago(n.createdAt)}',
              onTap: onTap,
            ),
        ],
      ),
    );
  }
}

// --- Encart d'information ------------------------------------------------------------

class _InfoBox extends StatelessWidget {
  const _InfoBox();

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
      child: SettingGroup(
        dividers: false,
        padding: const EdgeInsets.all(14),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration:
                    BoxDecoration(color: t.primarySoft, shape: BoxShape.circle),
                child: Icon(Icons.info_outline_rounded,
                    size: 18, color: t.onPrimarySoft),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: text.bodyMedium,
                    children: [
                      const TextSpan(text: "Ceci n'est qu'un aperçu. "),
                      TextSpan(
                        text: 'Crée ton compte étudiant',
                        style: TextStyle(
                            color: t.textPrimary, fontWeight: FontWeight.w700),
                      ),
                      const TextSpan(
                          text:
                              " pour publier, postuler, discuter et profiter de l'app hors-ligne."),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
