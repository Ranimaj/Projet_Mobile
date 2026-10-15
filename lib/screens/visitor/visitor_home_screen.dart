import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/article_provider.dart';
import '../../providers/annonce_provider.dart';
import '../../providers/event_provider.dart';
import '../../providers/job_provider.dart';

import '../auth/login_screen.dart';
import '../auth/register_screen.dart';

/// Accueil Visiteur (non connecté) — BF3 : donne un avant-goût réel de
/// chaque gestion (échantillons) pour donner envie de créer un compte,
/// sans exposer les actions qui nécessitent une authentification.
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
      context.read<ArticleProvider>().load();
      context.read<AnnonceProvider>().load();
      context.read<EventProvider>().load();
      context.read<JobProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHero(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildArticlesRow(context),
                    const SizedBox(height: 22),
                    _buildAnnoncesRow(context),
                    const SizedBox(height: 22),
                    _buildEventsRow(context),
                    const SizedBox(height: 22),
                    _buildJobsRow(context),
                    const SizedBox(height: 16),
                    _buildInfoBox(context),
                  ],
                ),
              ),
            ),
            _buildBottomCta(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 26),
      decoration: const BoxDecoration(gradient: AppColors.heroGradient),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              ),
              child: const Icon(Icons.home_rounded, color: Colors.white),
            ),
            const SizedBox(width: 10),
            const Text('CampusConnect',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 16),
          const Text(
            'Tout ton campus,\ndans une seule app',
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, height: 1.25),
          ),
          const SizedBox(height: 10),
          Text(
            "Échange, informe-toi, participe aux événements et trouve ton futur stage — avec les étudiants de ton école",
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBox(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, size: 17, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: RichText(
                text: const TextSpan(
                  style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.5),
                  children: [
                    TextSpan(text: "Ceci n'est qu'un aperçu. "),
                    TextSpan(
                      text: 'Crée ton compte étudiant',
                      style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: " pour publier, postuler, discuter et profiter de l'app hors-ligne."),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Text('Voir tout', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
        ],
      ),
    );
  }

  Widget _buildArticlesRow(BuildContext context) {
    final articles = context.watch<ArticleProvider>().items.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, 'Vente & Don'),
        const SizedBox(height: 10),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: articles.isEmpty ? 3 : articles.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              if (articles.isEmpty) {
                return _skeletonCard();
              }
              final a = articles[i];
              return Container(
                width: 128,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(14),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 84,
                      color: AppColors.categoryTints[i % AppColors.categoryTints.length],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(9),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 3),
                          Text(
                            a.isFree ? 'Gratuit' : '${a.price!.toStringAsFixed(0)} DT',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAnnoncesRow(BuildContext context) {
    final annonces = context.watch<AnnonceProvider>().publicPreview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, 'Annonces du campus'),
        const SizedBox(height: 10),
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: annonces.isEmpty ? 2 : annonces.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              if (annonces.isEmpty) return _skeletonCard(width: 220, height: 80);
              final a = annonces[i];
              final isOfficial = a.category == 'Officielle';
              return Container(
                width: 220,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isOfficial ? const Color(0xFFFFF7ED) : Colors.white,
                  border: Border.all(color: isOfficial ? const Color(0xFFFED7AA) : AppColors.border),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.isPinned ? 'ÉPINGLÉ · ${a.category.toUpperCase()}' : a.category.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: isOfficial ? AppColors.accent2 : AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(a.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.4)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEventsRow(BuildContext context) {
    final events = context.watch<EventProvider>().publicPreview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, 'Événements à venir'),
        const SizedBox(height: 10),
        SizedBox(
          height: 70,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: events.isEmpty ? 2 : events.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              if (events.isEmpty) return _skeletonCard(width: 160, height: 70);
              final e = events[i];
              return Container(
                width: 160,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(14),
                ),
                clipBehavior: Clip.antiAlias,
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      color: i.isEven ? AppColors.accent2 : AppColors.primary,
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(DateFormat('MMM', 'fr_FR').format(e.startDate).toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontSize: 10)),
                          Text(DateFormat('d').format(e.startDate),
                              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(e.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, height: 1.3)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildJobsRow(BuildContext context) {
    final jobs = context.watch<JobProvider>().offers.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, 'Stage & Emploi'),
        const SizedBox(height: 10),
        SizedBox(
          height: 66,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: jobs.isEmpty ? 2 : jobs.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              if (jobs.isEmpty) return _skeletonCard(width: 200, height: 66);
              final j = jobs[i];
              return Container(
                width: 200,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      alignment: Alignment.center,
                      child: Text(j.companyName.isNotEmpty ? j.companyName[0] : '?',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(j.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          Text('${j.companyName} · ${j.type.name == 'stage' ? 'Stage' : 'Emploi'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _skeletonCard({double width = 128, double height = 150}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.border.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }

  Widget _buildBottomCta(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, -4))],
      ),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: Container(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const RegisterScreen())),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: Text('Créer un compte étudiant',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Déjà inscrit ?', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              TextButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const LoginScreen())),
                child: const Text('Se connecter', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
