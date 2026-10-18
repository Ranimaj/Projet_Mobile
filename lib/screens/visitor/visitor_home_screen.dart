import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/layout.dart';
import '../../core/theme/app_colors.dart';
import '../../models/annonce_model.dart';
import '../../models/article_model.dart';
import '../../models/event_model.dart';
import '../../models/job_offer_model.dart';
import '../../providers/annonce_provider.dart';
import '../../providers/article_provider.dart';
import '../../providers/event_provider.dart';
import '../../providers/job_provider.dart';
import '../auth/login_screen.dart';
import '../auth/register_screen.dart';

/// Accueil Visiteur (non connecté) — BF3, fidèle à la maquette du cahier des
/// charges (section 7) : héro dégradé avec pastille et pastilles de chiffres,
/// puis un rail horizontal de cartes par gestion (Vente & Don, Annonces,
/// Événements, Stage & Emploi) avec « Voir tout », et l'appel à l'inscription
/// en pied d'écran. Les chiffres sont réels (jamais inventés).
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

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Hero(
                    students: _students,
                    notices: annonces.items.length,
                    companies: companies.length,
                  ),
                  const SizedBox(height: kSectionGap - 8),
                  _Section(
                    title: 'Vente & Don',
                    onSeeAll: _openLogin,
                    child: _Rail(
                      height: 150,
                      loading: articles.isLoading && forSale.isEmpty,
                      skeleton: const _Skeleton(width: 128, height: 150),
                      emptyText: 'Aucun objet proposé pour l\'instant.',
                      children: [
                        for (var i = 0; i < forSale.length; i++)
                          _ArticleCard(article: forSale[i], index: i)
                      ],
                    ),
                  ),
                  const SizedBox(height: kSectionGap - 8),
                  _Section(
                    title: 'Annonces du campus',
                    onSeeAll: _openLogin,
                    child: _Rail(
                      height: 92,
                      loading: annonces.isLoading && notices.isEmpty,
                      skeleton: const _Skeleton(width: 220, height: 84),
                      emptyText: 'Aucune annonce publiée pour l\'instant.',
                      children: [
                        for (final n in notices) _NoticeCard(notice: n)
                      ],
                    ),
                  ),
                  const SizedBox(height: kSectionGap - 8),
                  _Section(
                    title: 'Événements à venir',
                    onSeeAll: _openLogin,
                    child: _Rail(
                      height: 72,
                      loading: events.isLoading && upcoming.isEmpty,
                      skeleton: const _Skeleton(width: 160, height: 70),
                      emptyText: 'Aucun événement annoncé pour l\'instant.',
                      children: [
                        for (var i = 0; i < upcoming.length; i++)
                          _EventCard(event: upcoming[i], index: i)
                      ],
                    ),
                  ),
                  const SizedBox(height: kSectionGap - 8),
                  _Section(
                    title: 'Stage & Emploi',
                    onSeeAll: _openLogin,
                    child: _Rail(
                      height: 68,
                      loading: jobs.isLoading && offers.isEmpty,
                      skeleton: const _Skeleton(width: 200, height: 66),
                      emptyText: 'Aucune offre publiée pour l\'instant.',
                      children: [for (final j in offers) _OfferCard(offer: j)],
                    ),
                  ),
                  const SizedBox(height: kSectionGap - 8),
                  const _InfoBox(),
                  const SizedBox(height: kSectionGap - 8),
                ],
              ),
            ),
          ),
          _BottomCta(onRegister: _openRegister, onLogin: _openLogin),
        ],
      ),
    );
  }
}

// --- Héro --------------------------------------------------------------------------

class _Hero extends StatelessWidget {
  final Future<int> students;
  final int notices;
  final int companies;
  const _Hero(
      {required this.students, required this.notices, required this.companies});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const onHero = Colors.white;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(kPagePadding,
          MediaQuery.paddingOf(context).top + 12, kPagePadding, 24),
      decoration: const BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: onHero.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: onHero.withValues(alpha: 0.25)),
              ),
              child: const Icon(Icons.home_rounded, color: onHero, size: 22),
            ),
            const SizedBox(width: 10),
            Text('CampusConnect',
                style: text.titleLarge?.copyWith(color: onHero, fontSize: 18)),
          ]),
          const SizedBox(height: 18),
          Text(
            'Tout ton campus,\ndans une seule app',
            style: text.displayMedium?.copyWith(
                color: onHero,
                fontSize: 26,
                height: 1.2,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            'Échange, informe-toi, participe aux événements et trouve ton futur stage, avec les étudiants de ton école.',
            style: text.bodyMedium?.copyWith(
                color: onHero.withValues(alpha: 0.85),
                fontSize: 13.5,
                height: 1.4),
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
                  _StatPill(
                      value: n == null ? '…' : '$n',
                      label: n == 1 ? 'étudiant' : 'étudiants'),
                  _StatPill(
                      value: '$notices',
                      label: notices == 1 ? 'annonce' : 'annonces'),
                  _StatPill(
                      value: '$companies',
                      label: companies == 1 ? 'entreprise' : 'entreprises'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Pastille translucide « 12 annonces » du héro.
class _StatPill extends StatelessWidget {
  final String value;
  final String label;
  const _StatPill({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.white, fontSize: 13),
          children: [
            TextSpan(
                text: '$value ',
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            TextSpan(
                text: label,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
          ],
        ),
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
                  foregroundColor: AppColors.brandPrimary,
                  minimumSize: const Size(48, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: text.labelLarge?.copyWith(fontSize: 13),
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

/// Rail horizontal de cartes : squelettes pendant le chargement, texte sobre
/// quand il n'y a rien, cartes sinon.
class _Rail extends StatelessWidget {
  final double height;
  final bool loading;
  final Widget skeleton;
  final String emptyText;
  final List<Widget> children;

  const _Rail({
    required this.height,
    required this.loading,
    required this.skeleton,
    required this.emptyText,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    if (!loading && children.isEmpty) {
      return Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: kPagePadding, vertical: 8),
        child: Text(emptyText, style: Theme.of(context).textTheme.bodyMedium),
      );
    }
    final items = loading ? List<Widget>.filled(3, skeleton) : children;
    return SizedBox(
      height: height + 8,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(kPagePadding, 4, kPagePadding, 4),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) => items[i],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  final double width;
  final double height;
  const _Skeleton({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surfaceTone,
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}

BoxDecoration _card({Color color = Colors.white, Color? border}) =>
    BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(16),
      border: border == null ? null : Border.all(color: border),
      boxShadow: const [AppColors.cardShadow],
    );

// --- Cartes ---------------------------------------------------------------------------

class _ArticleCard extends StatelessWidget {
  final ArticleModel article;
  final int index;
  const _ArticleCard({required this.article, required this.index});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: 128,
      decoration: _card(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              color: AppColors
                  .categoryTints[index % AppColors.categoryTints.length],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(article.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(fontSize: 13)),
                const SizedBox(height: 4),
                if (article.isFree)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: AppColors.successTint,
                        borderRadius: BorderRadius.circular(8)),
                    child: const Text('Gratuit',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.successInk)),
                  )
                else
                  Text('${article.price!.toStringAsFixed(0)} DT',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final AnnonceModel notice;
  const _NoticeCard({required this.notice});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final official = notice.category == 'Officielle';
    final label = [
      if (notice.isPinned) 'Épinglé',
      official ? 'Officiel' : notice.category
    ].join(' · ');
    return Container(
      width: 220,
      padding: const EdgeInsets.all(12),
      decoration: _card(
        color: official ? AppColors.officialTint : Colors.white,
        border: official ? AppColors.officialBorder : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (notice.isPinned) ...[
              Icon(Icons.push_pin_rounded,
                  size: 13,
                  color: official ? AppColors.accent2 : AppColors.brandPrimary),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: official ? AppColors.accent2 : AppColors.brandPrimary,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(notice.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.titleSmall?.copyWith(
                  fontSize: 13,
                  height: 1.3,
                  color: official ? AppColors.officialInk : null)),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final EventModel event;
  final int index;
  const _EventCard({required this.event, required this.index});

  static const _months = [
    'JANV',
    'FÉVR',
    'MARS',
    'AVR',
    'MAI',
    'JUIN',
    'JUIL',
    'AOÛT',
    'SEPT',
    'OCT',
    'NOV',
    'DÉC'
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tile =
        index.isEven ? AppColors.accentGradient : AppColors.brandGradient;
    return Container(
      width: 184,
      decoration: _card(),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Container(
            width: 52,
            decoration: BoxDecoration(gradient: tile),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_months[event.startDate.month - 1],
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                Text('${event.startDate.day}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.1)),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(event.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(fontSize: 13, height: 1.3)),
            ),
          ),
        ],
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
    return Container(
      width: 200,
      padding: const EdgeInsets.all(10),
      decoration: _card(),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: Text(
                offer.companyName.isNotEmpty
                    ? offer.companyName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(offer.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(fontSize: 13)),
                Text(
                    '${offer.companyName} · ${offer.type == JobType.stage ? 'Stage' : 'Emploi'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- Encart d'information et appel à l'inscription ------------------------------------

class _InfoBox extends StatelessWidget {
  const _InfoBox();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _card(),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded,
                size: 18, color: AppColors.brandPrimary),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: text.bodyMedium?.copyWith(fontSize: 13, height: 1.5),
                  children: const [
                    TextSpan(text: "Ceci n'est qu'un aperçu. "),
                    TextSpan(
                      text: 'Crée ton compte étudiant',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700),
                    ),
                    TextSpan(
                        text:
                            " pour publier, postuler, discuter et profiter de l'app hors-ligne."),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomCta extends StatelessWidget {
  final VoidCallback onRegister;
  final VoidCallback onLogin;
  const _BottomCta({required this.onRegister, required this.onLogin});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(kPagePadding, 12, kPagePadding,
          12 + MediaQuery.paddingOf(context).bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Color(0x14000000), blurRadius: 16, offset: Offset(0, -4))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            height: 50,
            child: DecoratedBox(
              decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(14)),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onRegister,
                  child: const Center(
                    child: Text('Créer un compte étudiant',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Déjà inscrit ?',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontSize: 13)),
              TextButton(
                onPressed: onLogin,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.brandPrimary,
                  minimumSize: const Size(48, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Se connecter',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
