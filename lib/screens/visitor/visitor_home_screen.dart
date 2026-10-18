import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/layout.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/module_colors.dart';
import '../../models/annonce_model.dart';
import '../../models/article_model.dart';
import '../../models/event_model.dart';
import '../../models/job_offer_model.dart';
import '../../providers/annonce_provider.dart';
import '../../providers/article_provider.dart';
import '../../providers/event_provider.dart';
import '../../providers/job_provider.dart';
import '../../widgets/auth/auth_entrance.dart';
import '../auth/login_screen.dart';
import '../auth/register_screen.dart';

/// Accueil Visiteur (non connecté) — BF3.
///
/// La page dit ce que c'est en grand, donne les vrais chiffres du moment,
/// montre un échantillon réel de chaque gestion dans une composition
/// différente à chaque fois, et se referme sur le nom. Rien n'est inventé :
/// sans contenu, elle le dit.
///
/// Mise en œuvre Material 3 : couleurs et typographie tirées du thème et des
/// fichiers de constantes (`layout.dart`, `module_colors.dart`), marge
/// horizontale unique [kPagePadding], cibles tactiles ≥ 48 dp.
class VisitorHomeScreen extends StatefulWidget {
  const VisitorHomeScreen({super.key});

  @override
  State<VisitorHomeScreen> createState() => _VisitorHomeScreenState();
}

class _VisitorHomeScreenState extends State<VisitorHomeScreen> {
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

    final upcoming = events.publicPreview;
    final forSale = articles.items;
    final notices = annonces.items;
    final offers = jobs.offers;
    final loading = articles.isLoading ||
        annonces.isLoading ||
        events.isLoading ||
        jobs.isLoading;

    // Une poignée de sections, pas une longue liste : SingleChildScrollView +
    // Column (tout est construit, y compris la fin de page).
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Hero(onRegister: _openRegister, onLogin: _openLogin),
            _Section(
              title: 'En ce moment',
              child: _Pulse(
                loading: loading,
                events: upcoming.length,
                notices: notices.length,
                articles: forSale.length,
                offers: offers.length,
                onTap: _openLogin,
              ),
            ),
            _Section(
              title: 'Prochains événements',
              onSeeAll: upcoming.isEmpty ? null : _openLogin,
              child: upcoming.isEmpty
                  ? const _Empty(
                      icon: Icons.event_outlined,
                      text: 'Aucun événement annoncé pour l\'instant.')
                  : _EventList(events: upcoming.take(3).toList()),
            ),
            _Section(
              title: 'À vendre ou à donner',
              onSeeAll: forSale.isEmpty ? null : _openLogin,
              child: forSale.isEmpty
                  ? const _Empty(
                      icon: Icons.storefront_outlined,
                      text: 'Aucun objet proposé pour l\'instant.')
                  : _ArticleMosaic(articles: forSale.take(4).toList()),
            ),
            _Section(
              title: 'Annonces',
              onSeeAll: notices.isEmpty ? null : _openLogin,
              child: notices.isEmpty
                  ? const _Empty(
                      icon: Icons.campaign_outlined,
                      text: 'Aucune annonce publiée pour l\'instant.')
                  : _Notices(notices: notices.take(3).toList()),
            ),
            _Section(
              title: 'Stages et emplois',
              onSeeAll: offers.isEmpty ? null : _openLogin,
              child: offers.isEmpty
                  ? const _Empty(
                      icon: Icons.work_outline_rounded,
                      text: 'Aucune offre publiée pour l\'instant.')
                  : _OfferIndex(offers: offers.take(3).toList()),
            ),
            const SizedBox(height: kSectionGap),
            _Closing(onRegister: _openRegister, onLogin: _openLogin),
          ],
        ),
      ),
    );
  }
}

// --- Premier écran ---------------------------------------------------------------

class _Hero extends StatelessWidget {
  final VoidCallback onRegister;
  final VoidCallback onLogin;
  const _Hero({required this.onRegister, required this.onLogin});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final onPrimary = scheme.onPrimary;

    // Le fond (dégradé + cercles) est pleine largeur ; seul le contenu prend
    // la marge de page. Les cercles sont derrière le contenu et rognés.
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(kHeroBottomRadius)),
      child: DecoratedBox(
        decoration:
            const BoxDecoration(gradient: AppColors.visitorHeroGradient),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              top: -kHeroCircleLarge * 0.35,
              right: -kHeroCircleLarge * 0.25,
              child: _Circle(
                  size: kHeroCircleLarge,
                  color: onPrimary.withValues(alpha: 0.08)),
            ),
            Positioned(
              top: kHeroCircleLarge * 0.5,
              right: kHeroCircleSmall * 0.4,
              child: _Circle(
                  size: kHeroCircleSmall,
                  color: onPrimary.withValues(alpha: 0.08)),
            ),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    kPagePadding, 8, kPagePadding, 40),
                child: AuthEntrance(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'CampusConnect',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  text.titleLarge?.copyWith(color: onPrimary),
                            ),
                          ),
                          _LoginPill(onPressed: onLogin),
                        ],
                      ),
                      const SizedBox(height: 56),
                      Text('Le campus,\nen direct.',
                          style: text.displayLarge?.copyWith(color: onPrimary)),
                      const SizedBox(height: 16),
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                            maxWidth: kHeroSubtitleMaxWidth),
                        child: Text(
                          'Annonces, événements, petites annonces et stages, entre étudiants d\'ESPRIT.',
                          style: text.bodyLarge?.copyWith(
                            color: onPrimary.withValues(alpha: 0.85),
                            fontSize: 16,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      FilledButton.icon(
                        onPressed: onRegister,
                        style: FilledButton.styleFrom(
                          backgroundColor: onPrimary,
                          foregroundColor: AppColors.heroStart,
                          minimumSize: const Size(0, 56),
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          textStyle: text.titleMedium,
                        ),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                        label: const Text('Créer un compte étudiant'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// « Se connecter » : pilule contour de 36 dp (cible tactile 48 dp), bord
/// blanc 1 px, fond transparent, éclaboussure blanche à 10 %.
class _LoginPill extends StatelessWidget {
  final VoidCallback onPressed;
  const _LoginPill({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final onPrimary = Theme.of(context).colorScheme.onPrimary;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: onPrimary,
        backgroundColor: Colors.transparent,
        overlayColor: onPrimary.withValues(alpha: 0.10),
        side: BorderSide(color: onPrimary, width: 1),
        minimumSize: const Size(0, kPillHeight),
        fixedSize: const Size.fromHeight(kPillHeight),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        tapTargetSize: MaterialTapTargetSize.padded,
        shape: const StadiumBorder(),
        textStyle: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      child: const Text('Se connecter'),
    );
  }
}

class _Circle extends StatelessWidget {
  final double size;
  final Color color;
  const _Circle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}

// --- Chiffres du moment -------------------------------------------------------------

class _Pulse extends StatelessWidget {
  final bool loading;
  final int events;
  final int notices;
  final int articles;
  final int offers;
  final VoidCallback onTap;

  const _Pulse({
    required this.loading,
    required this.events,
    required this.notices,
    required this.articles,
    required this.offers,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final total = events + notices + articles + offers;

    if (total == 0) {
      return Text(
        loading
            ? 'Chargement du campus…'
            : 'Le campus démarre. Sois parmi les premiers à publier.',
        key: const Key('pulse'),
        style: text.headlineSmall?.copyWith(color: scheme.onSurfaceVariant),
      );
    }

    final tiles = [
      _StatData(events, 'événements à venir', Icons.event_rounded,
          ModuleColors.events),
      _StatData(
          notices, 'annonces', Icons.campaign_rounded, ModuleColors.notices),
      _StatData(articles, 'objets à vendre ou à donner',
          Icons.storefront_rounded, ModuleColors.market),
      _StatData(offers, 'offres de stage ou d\'emploi', Icons.work_rounded,
          ModuleColors.jobs),
    ];

    // Deux rangées de deux cartes : la hauteur épouse le contenu (pas de
    // ratio fixe), les deux cartes d'une rangée s'alignent (IntrinsicHeight).
    return Semantics(
      key: const Key('pulse'),
      label:
          'En ce moment : ${tiles.map((t) => '${t.count} ${t.label}').join(', ')}',
      child: Column(
        children: [
          for (var row = 0; row < tiles.length; row += 2) ...[
            if (row > 0) const SizedBox(height: kCardGap),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _StatCard(data: tiles[row], onTap: onTap)),
                  const SizedBox(width: kCardGap),
                  Expanded(
                    child: row + 1 < tiles.length
                        ? _StatCard(data: tiles[row + 1], onTap: onTap)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatData {
  final int count;
  final String label;
  final IconData icon;
  final Color accent;
  const _StatData(this.count, this.label, this.icon, this.accent);
}

/// Carte horizontale : pastille d'icône teintée à gauche, chiffre au-dessus
/// du libellé à droite. Blanche, rayon 20, ombre douce, cliquable.
class _StatCard extends StatelessWidget {
  final _StatData data;
  final VoidCallback onTap;
  const _StatCard({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(kStatCardRadius);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: radius,
        boxShadow: const [kStatCardShadow],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.all(kStatCardPadding),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: kIconTileSize,
                  height: kIconTileSize,
                  decoration: BoxDecoration(
                    color: ModuleColors.tint(data.accent),
                    borderRadius: BorderRadius.circular(kIconTileRadius),
                  ),
                  child: Icon(data.icon,
                      size: kIconTileIconSize, color: data.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${data.count}',
                        style: text.headlineSmall?.copyWith(
                          fontSize: 24,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          color: ModuleColors.countInk,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        data.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelLarge?.copyWith(
                          fontSize: 13,
                          height: 1.25,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
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

// --- Sections -----------------------------------------------------------------------

class _Section extends StatelessWidget {
  final String? title;
  final VoidCallback? onSeeAll;
  final Widget child;
  const _Section({this.title, this.onSeeAll, required this.child});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(
          left: kPagePadding, right: kPagePadding, top: kSectionGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                Expanded(child: Text(title!, style: text.displaySmall)),
                if (onSeeAll != null)
                  TextButton(
                    onPressed: onSeeAll,
                    style:
                        TextButton.styleFrom(minimumSize: const Size(48, 48)),
                    child: const Text('Tout voir'),
                  ),
              ],
            ),
            const SizedBox(height: kHeaderGap),
          ],
          child,
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Empty({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      color: scheme.surface,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, color: scheme.onSurfaceVariant),
        title: Text(text,
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: scheme.onSurfaceVariant)),
      ),
    );
  }
}

/// Liste datée : la date dans une tuile tonale, le titre, le lieu.
class _EventList extends StatelessWidget {
  final List<EventModel> events;
  const _EventList({required this.events});

  static const _months = [
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card.filled(
      margin: EdgeInsets.zero,
      color: scheme.surface,
      child: Column(
        children: [
          for (final e in events)
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                // FittedBox : la tuile garde 56 dp quelle que soit la police.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${e.startDate.day}',
                          style: text.titleLarge?.copyWith(
                              color: scheme.onPrimaryContainer, height: 1)),
                      Text(_months[e.startDate.month - 1],
                          style: text.labelLarge
                              ?.copyWith(color: scheme.onPrimaryContainer)),
                    ],
                  ),
                ),
              ),
              title: Text(e.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  [e.location, e.organizerName]
                      .where((s) => s.isNotEmpty)
                      .join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Mosaïque deux colonnes : un aplat de couleur par objet, le prix en grand.
/// Deux rangées de cartes dont la hauteur épouse le contenu (pas de ratio
/// fixe) : aucune troncature à 360 px ni avec une grande police.
class _ArticleMosaic extends StatelessWidget {
  final List<ArticleModel> articles;
  const _ArticleMosaic({required this.articles});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var row = 0; row < articles.length; row += 2) ...[
          if (row > 0) const SizedBox(height: kCardGap),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                    child: _ArticleCard(article: articles[row], index: row)),
                const SizedBox(width: kCardGap),
                Expanded(
                  child: row + 1 < articles.length
                      ? _ArticleCard(article: articles[row + 1], index: row + 1)
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
  const _ArticleCard({required this.article, required this.index});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      color: AppColors.categoryTints[index % AppColors.categoryTints.length],
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                label: Text(article.category),
                labelStyle: text.labelLarge?.copyWith(color: scheme.onSurface),
                backgroundColor: scheme.surface.withValues(alpha: 0.6),
                side: BorderSide.none,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(height: 24),
            Text(article.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium),
            const SizedBox(height: 8),
            Text(
              article.isFree
                  ? 'Gratuit'
                  : '${article.price!.toStringAsFixed(0)} DT',
              style: text.headlineMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// La première annonce (épinglée ou officielle d'abord) est posée en énoncé
/// dans une carte tonale ; les suivantes sont des lignes de liste.
class _Notices extends StatelessWidget {
  final List<AnnonceModel> notices;
  const _Notices({required this.notices});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final sorted = [...notices]..sort((a, b) {
        int rank(AnnonceModel n) =>
            (n.isPinned ? 0 : 2) + (n.category == 'Officielle' ? 0 : 1);
        return rank(a).compareTo(rank(b));
      });
    final lead = sorted.first;
    final rest = sorted.skip(1).toList();

    Chip tag(IconData icon, String label) => Chip(
          avatar: Icon(icon, size: 18, color: scheme.onSecondaryContainer),
          label: Text(label),
          labelStyle:
              text.labelLarge?.copyWith(color: scheme.onSecondaryContainer),
          backgroundColor: scheme.surface.withValues(alpha: 0.5),
          side: BorderSide.none,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card.filled(
          margin: EdgeInsets.zero,
          color: scheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    tag(
                        lead.category == 'Officielle'
                            ? Icons.verified_rounded
                            : Icons.campaign_rounded,
                        lead.category),
                    if (lead.isPinned) tag(Icons.push_pin_rounded, 'Épinglée'),
                  ],
                ),
                const SizedBox(height: 16),
                Text(lead.title,
                    style: text.headlineMedium
                        ?.copyWith(color: scheme.onSecondaryContainer)),
                const SizedBox(height: 8),
                Text(
                  lead.content,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyLarge
                      ?.copyWith(color: scheme.onSecondaryContainer),
                ),
                const SizedBox(height: 16),
                Text(lead.authorName,
                    style: text.labelLarge?.copyWith(
                        color: scheme.onSecondaryContainer
                            .withValues(alpha: 0.8))),
              ],
            ),
          ),
        ),
        if (rest.isNotEmpty) ...[
          const SizedBox(height: kCardGap),
          Card.filled(
            margin: EdgeInsets.zero,
            color: scheme.surface,
            child: Column(
              children: [
                for (final n in rest)
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: Icon(
                      n.category == 'Perdu & Trouvé'
                          ? Icons.search_rounded
                          : Icons.campaign_outlined,
                      color: scheme.primary,
                    ),
                    title: Text(n.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium),
                    subtitle: Text('${n.category} · ${n.authorName}',
                        style: text.bodyMedium),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Index : l'initiale de l'entreprise dans une pastille tonale, le poste,
/// l'entreprise et le lieu, le type en puce.
class _OfferIndex extends StatelessWidget {
  final List<JobOfferModel> offers;
  const _OfferIndex({required this.offers});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card.filled(
      margin: EdgeInsets.zero,
      color: scheme.surface,
      child: Column(
        children: [
          for (final j in offers)
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                radius: 24,
                backgroundColor: scheme.tertiaryContainer,
                foregroundColor: scheme.onTertiaryContainer,
                child: Text(
                    j.companyName.isNotEmpty
                        ? j.companyName[0].toUpperCase()
                        : '?',
                    style: text.titleLarge
                        ?.copyWith(color: scheme.onTertiaryContainer)),
              ),
              title: Text(j.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  [j.companyName, j.location]
                      .where((s) => s.isNotEmpty)
                      .join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium,
                ),
              ),
              trailing: Chip(
                label: Text(j.type == JobType.stage ? 'Stage' : 'Emploi'),
                labelStyle: text.labelLarge?.copyWith(color: scheme.onSurface),
                side: BorderSide.none,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
    );
  }
}

// --- Fin de page : le nom, en grand --------------------------------------------------

class _Closing extends StatelessWidget {
  final VoidCallback onRegister;
  final VoidCallback onLogin;
  const _Closing({required this.onRegister, required this.onLogin});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final onField = scheme.onPrimary;

    return Material(
      color: AppColors.authField,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              kPagePadding, 48, kPagePadding, kSectionGap),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('CampusConnect',
                    style: text.displayLarge
                        ?.copyWith(color: onField, fontSize: 52)),
              ),
              const SizedBox(height: 16),
              Text(
                'Réservé aux étudiants d\'ESPRIT, avec leur email académique.',
                style: text.bodyLarge?.copyWith(
                    color: onField.withValues(alpha: 0.88), fontSize: 16),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: onRegister,
                style: FilledButton.styleFrom(
                  backgroundColor: onField,
                  foregroundColor: AppColors.authField,
                  minimumSize: const Size(0, 56),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  textStyle: text.titleMedium,
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                label: const Text('Créer un compte étudiant'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: onLogin,
                style: TextButton.styleFrom(
                  foregroundColor: onField,
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: text.titleSmall,
                ),
                child: const Text('Déjà inscrit ? Se connecter'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
