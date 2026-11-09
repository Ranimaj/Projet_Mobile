import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/layout.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../models/job_offer_model.dart';
import '../../../services/stages/admin_stats.dart';
import '../../../services/stages/stage_services.dart';
import '../../../widgets/stages/ui.dart';
import '../../../widgets/charts/chart_models.dart';
import '../../../widgets/charts/donut_chart.dart';
import '../../../widgets/section_card.dart';
import '../../../widgets/stat_tile.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DetailPage(
      title: 'Suivi des stages',
      children: [
        DbBuilder<AdminStats>(
          load: (s) => s.adminStats(),
          builder: (context, stats) {
            final t = AppTokens.of(context);
            final emailsConfigured = context.read<StageServices>().emails.isConfigured;
            final colors = {
              ApplicationStatus.pending: t.textSecondary,
              ApplicationStatus.hrInterview: t.primary,
              ApplicationStatus.technicalInterview: t.warning,
              ApplicationStatus.accepted: t.success,
              ApplicationStatus.rejected: t.danger,
            };
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Grid(tiles: [
                  StatTile(value: '${stats.openJobs}/${stats.totalJobs}', label: 'Offres ouvertes'),
                  StatTile(value: '${stats.totalApplications}', label: 'Candidatures'),
                ]),
                const SectionTitle('Candidatures par étape'),
                AppCard(
                  child: DonutChart(
                    centerLabel: '${stats.totalApplications}',
                    emptyText: 'Aucune candidature pour le moment',
                    slices: [
                      for (final e in stats.applicationsByStatus.entries)
                        if (e.value > 0) ChartSlice(label: e.key.label, value: e.value.toDouble(), color: colors[e.key]!),
                    ],
                  ),
                ),
                const SectionTitle('Emails'),
                _Grid(tiles: [
                  StatTile(value: '${stats.emailsSent}', label: 'Envoyés', valueColor: t.success),
                  StatTile(value: '${stats.emailsWaiting}', label: 'En attente', valueColor: t.warning),
                ]),
                const SizedBox(height: kCardGap),
                StatTile(value: '${stats.emailsFailed}', label: 'En échec', valueColor: t.danger),
                const SectionTitle('Services'),
                SectionCard(
                  children: [
                    SettingsTile(
                      icon: Icons.outgoing_mail,
                      label: 'SMTP Gmail',
                      subtitle: emailsConfigured ? 'Configuré' : 'À configurer (.env.json)',
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: kCardGap),
          Row(
            children: [
              Expanded(child: tiles[i]),
              const SizedBox(width: kCardGap),
              Expanded(child: tiles[i + 1]),
            ],
          ),
        ],
      ],
    );
  }
}
