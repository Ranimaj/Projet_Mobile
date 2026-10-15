import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/job_offer_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/job_provider.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/offline_banner.dart';
import 'add_job_screen.dart';
import 'job_detail_screen.dart';
import 'my_applications_screen.dart';

/// BF10/BF11 — offres de stage/emploi + bannière de recommandations
/// basées sur le matching intelligent (fonctionnalité avancée).
class StagesListScreen extends StatefulWidget {
  const StagesListScreen({super.key});

  @override
  State<StagesListScreen> createState() => _StagesListScreenState();
}

class _StagesListScreenState extends State<StagesListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<JobProvider>().load();
      final auth = context.read<AuthProvider>();
      if (auth.currentUser != null) {
        context.read<JobProvider>().loadMyApplications(auth.currentUser!.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<JobProvider>();
    final auth = context.watch<AuthProvider>();
    final isGuest = auth.status != AuthStatus.authenticated;
    final isRecruiter = auth.currentUser?.role.name == 'recruiter';
    final recommended = auth.currentUser == null
        ? <JobOfferModel>[]
        : provider.recommendedFor(auth.currentUser!.skills);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stage & Emploi'),
        actions: [
          if (!isGuest)
            IconButton(
              icon: const Icon(Icons.assignment_turned_in_outlined),
              tooltip: 'Mes candidatures',
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const MyApplicationsScreen())),
            ),
        ],
      ),
      floatingActionButton: isRecruiter
          ? FloatingActionButton(
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const AddJobScreen())),
              child: const Icon(Icons.add_rounded),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            const OfflineBanner(),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                children: [
                  _Chip(label: 'Toutes', selected: provider.typeFilter == null,
                      onTap: () => provider.setTypeFilter(null)),
                  const SizedBox(width: 8),
                  _Chip(label: 'Stages', selected: provider.typeFilter == 'stage',
                      onTap: () => provider.setTypeFilter(provider.typeFilter == 'stage' ? null : 'stage')),
                  const SizedBox(width: 8),
                  _Chip(label: 'Emplois', selected: provider.typeFilter == 'emploi',
                      onTap: () => provider.setTypeFilter(provider.typeFilter == 'emploi' ? null : 'emploi')),
                ],
              ),
            ),
            Expanded(
              child: provider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : provider.offers.isEmpty
                      ? const EmptyState(
                          icon: Icons.work_outline_rounded,
                          title: 'Aucune offre pour le moment',
                          subtitle: 'Les stages et emplois publiés par les recruteurs apparaîtront ici.',
                        )
                      : RefreshIndicator(
                          onRefresh: provider.load,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 90),
                            children: [
                              if (recommended.isNotEmpty) ...[
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    gradient: AppColors.heroGradient,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          '${recommended.length} offre(s) correspondent à votre profil',
                                          style: const TextStyle(
                                              color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                              ],
                              ...provider.offers.map((o) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _JobCard(
                                      offer: o,
                                      matchPct: auth.currentUser == null
                                          ? null
                                          : (o.matchScore(auth.currentUser!.skills) * 100).round(),
                                    ),
                                  )),
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

class _JobCard extends StatelessWidget {
  final JobOfferModel offer;
  final int? matchPct;
  const _JobCard({required this.offer, this.matchPct});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => JobDetailScreen(offer: offer))),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: offer.type == JobType.stage
                        ? const Color(0xFFDBEAFE)
                        : const Color(0xFFD1FAE5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    offer.type == JobType.stage ? 'STAGE' : 'EMPLOI',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: offer.type == JobType.stage ? const Color(0xFF1E40AF) : const Color(0xFF065F46)),
                  ),
                ),
                const Spacer(),
                if (matchPct != null && matchPct! > 0)
                  Text('$matchPct% match',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.accent2)),
              ],
            ),
            const SizedBox(height: 8),
            Text(offer.title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text('${offer.companyName} · ${offer.location}',
                style: Theme.of(context).textTheme.bodyMedium),
            if (offer.requiredSkills.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: offer.requiredSkills.take(4).map((s) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(s, style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
                    )).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: selected ? Colors.white : AppColors.textSecondary)),
      ),
    );
  }
}
