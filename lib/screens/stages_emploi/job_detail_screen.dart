import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/job_offer_model.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/primary_button.dart';
import 'apply_screen.dart';

/// Détail d'une offre — compétences requises, score de correspondance,
/// bouton de candidature.
class JobDetailScreen extends StatelessWidget {
  final JobOfferModel offer;
  const JobDetailScreen({super.key, required this.offer});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isGuest = auth.status != AuthStatus.authenticated;
    final score = auth.currentUser == null ? 0 : (offer.matchScore(auth.currentUser!.skills) * 100).round();

    return Scaffold(
      appBar: AppBar(title: const Text('Offre')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: offer.type == JobType.stage ? const Color(0xFFDBEAFE) : const Color(0xFFD1FAE5),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                offer.type == JobType.stage ? 'STAGE' : 'EMPLOI',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: offer.type == JobType.stage ? const Color(0xFF1E40AF) : const Color(0xFF065F46)),
              ),
            ),
            const SizedBox(height: 10),
            Text(offer.title, style: Theme.of(context).textTheme.displayMedium),
            const SizedBox(height: 6),
            Text('${offer.companyName} · ${offer.location}', style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 4),
            Text('Publiée le ${DateFormat('d MMM yyyy', 'fr_FR').format(offer.postedAt)}',
                style: Theme.of(context).textTheme.bodyMedium),
            if (score > 0) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: AppColors.heroGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text('$score% de correspondance avec votre profil',
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
            const SizedBox(height: 18),
            Text('Description', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(offer.description, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6)),
            if (offer.requiredSkills.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('Compétences requises', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: offer.requiredSkills.map((s) {
                  final has = auth.currentUser?.skills
                          .any((c) => c.toLowerCase() == s.toLowerCase()) ??
                      false;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: has ? const Color(0xFFD1FAE5) : AppColors.background,
                      border: Border.all(color: has ? const Color(0xFF10B981) : AppColors.border),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(s,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: has ? const Color(0xFF065F46) : AppColors.textSecondary)),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 26),
            if (!isGuest)
              PrimaryButton(
                label: 'Postuler maintenant',
                icon: Icons.send_rounded,
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => ApplyScreen(offer: offer))),
              )
            else
              Text('Connectez-vous pour postuler à cette offre.', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
