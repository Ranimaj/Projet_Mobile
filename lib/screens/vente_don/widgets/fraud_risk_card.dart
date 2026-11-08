import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../models/article_model.dart';
import '../../../services/ai/fraud_detector.dart';

/// Analyse anti-arnaque montrée à l'acheteur sur la page d'un article :
/// niveau de risque, probabilité et indices trouvés par le modèle embarqué.
class FraudRiskCard extends StatelessWidget {
  final ArticleModel article;
  const FraudRiskCard({super.key, required this.article});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FraudModel>(
      future: FraudModel.load(),
      builder: (context, snap) {
        final model = snap.data;
        if (model == null) return const SizedBox.shrink();
        return _Card(report: model.analyzeArticle(article));
      },
    );
  }
}

class _Card extends StatelessWidget {
  final FraudReport report;
  const _Card({required this.report});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final (color, soft, icon, title, advice) = switch (report.risk) {
      FraudRisk.low => (
          t.success,
          t.successSoft,
          Icons.verified_user_outlined,
          'Risque d\'arnaque faible',
          'Aucun signe d\'arnaque détecté. Rencontre quand même le vendeur sur le campus.',
        ),
      FraudRisk.medium => (
          t.warning,
          t.warningSoft,
          Icons.shield_outlined,
          'Risque d\'arnaque moyen',
          'Sois prudent : vois l\'objet avant de payer.',
        ),
      FraudRisk.high => (
          t.danger,
          t.dangerSoft,
          Icons.gpp_bad_outlined,
          'Risque d\'arnaque élevé',
          'Cette annonce ressemble à une arnaque. Ne paie jamais à l\'avance.',
        ),
    };
    return Container(
      key: const Key('fraud-card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    key: const Key('fraud-level'), style: text.titleSmall?.copyWith(color: color)),
              ),
              Text('${report.percent} %', style: text.labelLarge?.copyWith(color: color)),
            ],
          ),
          const SizedBox(height: 6),
          Text(advice, style: text.bodyMedium),
          if (report.risk != FraudRisk.low)
            for (final reason in report.reasons)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: text.bodyMedium?.copyWith(color: color)),
                    Expanded(child: Text(reason, style: text.bodyMedium)),
                  ],
                ),
              ),
          const SizedBox(height: 6),
          Text('Analyse par l\'IA de CampusConnect, dans ton téléphone.', style: text.labelSmall),
        ],
      ),
    );
  }
}
