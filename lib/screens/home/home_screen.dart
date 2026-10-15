import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/job_provider.dart';
import '../../widgets/offline_banner.dart';
import '../vente_don/vente_don_list_screen.dart';
import '../annonces/annonces_list_screen.dart';
import '../evenements/evenements_list_screen.dart';
import '../stages_emploi/stages_list_screen.dart';
import '../profile/profile_screen.dart';

/// Hub central affiché après connexion — BF13 : tableau de bord donnant
/// accès aux 5 gestions depuis un point d'entrée unique.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      if (auth.currentUser != null) {
        context.read<JobProvider>().loadMyApplications(auth.currentUser!.id);
      }
    });
  }

  void _openTab(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              decoration: const BoxDecoration(gradient: AppColors.heroGradient),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Bonjour 👋', style: TextStyle(color: Color(0xFFE0E7FF), fontSize: 12)),
                          Text(user?.fullName ?? 'Étudiant',
                              style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      CircleAvatar(
                        radius: 21,
                        backgroundColor: Colors.white.withValues(alpha: 0.18),
                        child: Text(user?.initials ?? '?',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                    child: const Row(children: [
                      Icon(Icons.search_rounded, size: 18, color: AppColors.textSecondary),
                      SizedBox(width: 8),
                      Text('Rechercher sur CampusConnect…',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    ]),
                  ),
                ],
              ),
            ),
            const OfflineBanner(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('MES MODULES', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.35,
                      children: [
                        _ModuleCard(
                          icon: Icons.person_rounded,
                          label: 'Mon profil',
                          color: AppColors.primary,
                          bg: const Color(0xFFEEF2FF),
                          onTap: () => _openTab(const ProfileScreen()),
                        ),
                        _ModuleCard(
                          icon: Icons.storefront_rounded,
                          label: 'Vente & Don',
                          color: AppColors.accent2,
                          bg: const Color(0xFFFFF7ED),
                          onTap: () => _openTab(const VenteDonListScreen()),
                        ),
                        _ModuleCard(
                          icon: Icons.campaign_rounded,
                          label: 'Annonces',
                          color: AppColors.success,
                          bg: const Color(0xFFECFDF5),
                          onTap: () => _openTab(const AnnoncesListScreen()),
                        ),
                        _ModuleCard(
                          icon: Icons.event_rounded,
                          label: 'Événements',
                          color: AppColors.danger,
                          bg: const Color(0xFFFEF2F2),
                          onTap: () => _openTab(const EvenementsListScreen()),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _JobsBanner(onTap: () => _openTab(const StagesListScreen())),
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

class _ModuleCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color bg;
  final VoidCallback onTap;

  const _ModuleCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.bg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _JobsBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _JobsBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final offersCount = context.watch<JobProvider>().offers.length;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.work_rounded, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Stage & Emploi', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    Text('$offersCount offres disponibles',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
