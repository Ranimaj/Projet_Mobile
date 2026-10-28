import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/layout.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/user_model.dart';
import '../../providers/admin_users_provider.dart';
import '../../services/user_stats_service.dart';
import '../../widgets/charts/area_line_chart.dart';
import '../../widgets/charts/chart_models.dart';
import '../../widgets/charts/donut_chart.dart';
import '../../widgets/charts/h_bar_chart.dart';
import '../../widgets/filter_chip_pill.dart';
import '../../widgets/skeleton_box.dart';
import '../../widgets/stat_tile.dart';

/// Statistiques d'inscription et de vérification des cartes, calculées à
/// partir des comptes déjà chargés par [AdminUsersProvider].
class AdminAnalyticsScreen extends StatefulWidget {
  /// Horloge injectable pour les tests.
  final DateTime Function()? now;

  const AdminAnalyticsScreen({super.key, this.now});

  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> {
  static const _periods = [7, 30, 90];
  int _days = 30;

  String get _periodLabel => switch (_days) {
        7 => 'cette semaine',
        30 => 'ce mois',
        _ => 'sur 3 mois',
      };

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminUsersProvider>();
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;

    Widget body;
    if (provider.isLoading) {
      body = const Padding(
        padding: EdgeInsets.all(kPagePadding),
        child: SkeletonBox(height: 160),
      );
    } else {
      final stats = aggregate(provider.users,
          now: (widget.now ?? DateTime.now)(), days: _days);
      final change = stats.changePercent;
      final delta = change == null
          ? null
          : '${change >= 0 ? '+' : '−'} ${change.abs().round()} % $_periodLabel';

      Widget section(String title, Widget chart) => Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 10),
                  child: Text(title, style: text.titleSmall),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: t.outline),
                  ),
                  child: chart,
                ),
              ],
            ),
          );

      body = ListView(
        padding: const EdgeInsets.fromLTRB(kPagePadding, 8, kPagePadding, 32),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final days in _periods) ...[
                  FilterChipPill(
                    label: '$days j',
                    selected: _days == days,
                    onTap: () => setState(() => _days = days),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    StatTile(value: '${stats.signUps}', label: 'Inscrits'),
                    if (delta != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          delta,
                          textAlign: TextAlign.center,
                          style: text.labelMedium!.copyWith(
                            color: change! >= 0 ? t.success : t.danger,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatTile(
                  value: '${stats.pendingCards}',
                  label: 'Cartes en attente',
                  valueColor: t.primary,
                ),
              ),
            ],
          ),
          section(
            'Inscriptions par jour',
            AreaLineChart(
              points: stats.signUpsPerDay,
              emptyText: 'Aucune inscription sur la période',
              tooltip: (p) => '+${p.value.round()}',
            ),
          ),
          section(
            'Par rôle',
            DonutChart(
              centerLabel: '${provider.users.length}',
              emptyText: 'Aucun utilisateur',
              slices: [
                ChartSlice(
                  label: 'Étudiants',
                  value: (stats.byRole[UserRole.student] ?? 0).toDouble(),
                  color: t.primary,
                ),
                ChartSlice(
                  label: 'Recruteurs',
                  value: (stats.byRole[UserRole.recruiter] ?? 0).toDouble(),
                  color: t.primary.withValues(alpha: 0.6),
                ),
                ChartSlice(
                  label: 'Admins',
                  value: (stats.byRole[UserRole.admin] ?? 0).toDouble(),
                  color: t.textSecondary,
                ),
              ],
            ),
          ),
          section(
            'Vérification des cartes',
            HBarChart(
              emptyText: 'Aucune carte envoyée',
              bars: [
                ChartBar(
                  label: 'Validées',
                  value: (stats.cardsByStatus[StudentCardStatus.verified] ?? 0)
                      .toDouble(),
                  color: t.primary,
                ),
                ChartBar(
                  label: 'En attente',
                  value: stats.pendingCards.toDouble(),
                  color: t.warning,
                ),
                ChartBar(
                  label: 'Refusées',
                  value: (stats.cardsByStatus[StudentCardStatus.rejected] ?? 0)
                      .toDouble(),
                  color: t.handle,
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(title: const Text('Statistiques')),
      body: body,
    );
  }
}
