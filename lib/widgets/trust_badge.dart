import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_tokens.dart';
import '../core/utils/trust_score.dart';
import '../models/article_model.dart';
import '../models/user_model.dart';
import '../providers/article_provider.dart';

/// Couleur de chaque niveau (médaille).
Color trustColor(BuildContext context, TrustLevel level) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (level) {
    TrustLevel.nouveau => AppTokens.of(context).textSecondary,
    TrustLevel.bronze => dark ? const Color(0xFFE0A070) : const Color(0xFF9A5A22),
    TrustLevel.argent => dark ? const Color(0xFFC3CCD8) : const Color(0xFF55606E),
    TrustLevel.or => dark ? const Color(0xFFF2C94C) : const Color(0xFF8A6100),
  };
}

/// Pastille « Or · 86 » ; un appui ouvre le détail du score.
class TrustBadge extends StatelessWidget {
  final TrustScore trust;

  /// Montre les conseils pour progresser (le badge de l'utilisateur lui-même).
  final bool own;
  final bool showScore;

  const TrustBadge({super.key, required this.trust, this.own = false, this.showScore = true});

  @override
  Widget build(BuildContext context) {
    final color = trustColor(context, trust.level);
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: 'Confiance ${trust.level.label}, ${trust.score} sur 100',
      child: InkWell(
        key: const Key('trust-badge'),
        borderRadius: BorderRadius.circular(20),
        onTap: () => showTrustDetails(context, trust, own: own),
        // Zone d'appui de 48 dp ; la pastille reste petite au centre.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                        trust.level == TrustLevel.nouveau
                            ? Icons.eco_rounded
                            : Icons.workspace_premium_rounded,
                        size: 16,
                        color: color),
                    const SizedBox(width: 4),
                    Text(
                      showScore ? '${trust.level.label} · ${trust.score}' : trust.level.label,
                      style: text.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w700),
                    ),
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

/// Détail du score : chaque critère, les points perdus, et (pour soi) comment
/// progresser.
Future<void> showTrustDetails(BuildContext context, TrustScore trust, {bool own = false}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      final t = AppTokens.of(context);
      final text = Theme.of(context).textTheme;
      final color = trustColor(context, trust.level);
      final toNext = trust.pointsToNextLevel;
      return SafeArea(
        child: SingleChildScrollView(
          key: const Key('trust-details'),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.workspace_premium_rounded, color: color, size: 32),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Confiance ${trust.level.label}', style: text.titleLarge),
                        Text('${trust.score} / 100',
                            style: text.bodyMedium?.copyWith(color: t.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
              if (own && toNext != null) ...[
                const SizedBox(height: 8),
                Text('Encore $toNext points pour le niveau ${trust.level.next!.label}.',
                    style: text.bodyMedium),
              ],
              const SizedBox(height: 16),
              for (final f in trust.factors) _FactorRow(factor: f, showTip: own),
              if (trust.penalty > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(Icons.report_rounded, size: 18, color: t.danger),
                      const SizedBox(width: 8),
                      Expanded(child: Text('Signalements confirmés', style: text.bodyMedium)),
                      Text('−${trust.penalty}', style: text.labelLarge?.copyWith(color: t.danger)),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                'Le score combine les vérifications du compte, son ancienneté, les ventes conclues et les '
                'avis. Il aide à repérer les profils fiables, mais rencontre toujours la personne sur le campus.',
                style: text.bodySmall?.copyWith(color: t.textSecondary),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _FactorRow extends StatelessWidget {
  final TrustFactor factor;
  final bool showTip;
  const _FactorRow({required this.factor, required this.showTip});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(factor.complete ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  size: 18, color: factor.complete ? t.success : t.textSecondary),
              const SizedBox(width: 8),
              Expanded(child: Text(factor.label, style: text.bodyMedium)),
              Text('${factor.points}/${factor.max}', style: text.labelLarge),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: factor.max == 0 ? 0 : factor.points / factor.max,
              minHeight: 4,
              backgroundColor: t.surfaceMuted,
              color: factor.complete ? t.success : t.primary,
            ),
          ),
          if (showTip && !factor.complete && factor.tip != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(factor.tip!, style: text.bodySmall?.copyWith(color: t.textSecondary)),
            ),
        ],
      ),
    );
  }
}

/// Charge un profil public (`users/{uid}`).
typedef PublicUserLoader = Future<AppUser?> Function(String uid);

Future<AppUser?> loadPublicUser(String uid) async {
  try {
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data();
    return data == null ? null : AppUser.fromMap(doc.id, data);
  } catch (_) {
    return null; // hors-ligne ou Firebase indisponible : pas de badge
  }
}

/// Articles vendus ou donnés par [userId], d'après les annonces chargées.
int completedSalesOf(BuildContext context, String userId) {
  try {
    return context
        .read<ArticleProvider>()
        .all
        .where((a) => a.ownerId == userId && a.status == ArticleStatus.done)
        .length;
  } catch (_) {
    return 0; // pas de ArticleProvider au-dessus (écran isolé)
  }
}

/// Charge le profil de [userId] et construit son score de confiance.
/// [builder] reçoit `null` tant que le profil n'est pas chargé (ou s'il est
/// introuvable).
class UserTrust extends StatefulWidget {
  final String userId;
  final PublicUserLoader? loader;
  final Widget Function(BuildContext context, TrustScore? trust, AppUser? user) builder;

  const UserTrust({super.key, required this.userId, required this.builder, this.loader});

  @override
  State<UserTrust> createState() => _UserTrustState();
}

class _UserTrustState extends State<UserTrust> {
  late Future<AppUser?> _user = (widget.loader ?? loadPublicUser)(widget.userId);

  @override
  void didUpdateWidget(UserTrust old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId) _user = (widget.loader ?? loadPublicUser)(widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUser?>(
      future: _user,
      builder: (context, snap) {
        final user = snap.data;
        final trust =
            user == null ? null : TrustScore.of(user, completedSales: completedSalesOf(context, user.id));
        return widget.builder(context, trust, user);
      },
    );
  }
}
