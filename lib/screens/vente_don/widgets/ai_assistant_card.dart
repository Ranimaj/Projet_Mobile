import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../services/ai/category_mapper.dart';
import '../../../services/ai/price_advisor.dart';
import '../../../widgets/pill_button.dart';

/// Carte « Assistant IA » du formulaire de publication : catégorie et
/// mots-clés reconnus sur la photo, prix conseillé et rédaction de la
/// description.
class AiAssistantCard extends StatelessWidget {
  final bool analyzing;
  final bool analysisFailed;
  final CategorySuggestion? suggestion;
  final bool categoryApplied;
  final VoidCallback? onApplyCategory;
  final ValueChanged<String> onKeyword;
  final PriceAdvice? priceAdvice;
  final bool isFree;
  final VoidCallback? onUsePrice;
  final bool writing;
  final bool online;
  final VoidCallback onWrite;

  const AiAssistantCard({
    super.key,
    required this.analyzing,
    required this.analysisFailed,
    required this.suggestion,
    required this.categoryApplied,
    required this.onApplyCategory,
    required this.onKeyword,
    required this.priceAdvice,
    required this.isFree,
    required this.onUsePrice,
    required this.writing,
    required this.online,
    required this.onWrite,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final s = suggestion;
    final advice = priceAdvice;

    Widget row(IconData icon, Widget child, {Widget? action}) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: t.primary),
              const SizedBox(width: 10),
              Expanded(child: child),
              if (action != null) action,
            ],
          ),
        );

    return Container(
      key: const Key('ai-assistant'),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: t.primarySoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: t.primary),
              const SizedBox(width: 8),
              Text('Assistant IA', style: text.titleMedium),
            ],
          ),
          if (analyzing)
            row(
              Icons.image_search_rounded,
              Text('Analyse de la photo…', key: const Key('ai-analyzing'), style: text.bodyMedium),
              action: const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (s != null) ...[
            row(
              Icons.category_outlined,
              Text(
                categoryApplied
                    ? 'Catégorie reconnue : ${s.category} (${(s.confidence * 100).round()} %)'
                    : 'La photo ressemble à : ${s.category} (${(s.confidence * 100).round()} %)',
                key: const Key('ai-category'),
                style: text.bodyMedium,
              ),
              action: categoryApplied
                  ? null
                  : TextButton(
                      key: const Key('ai-apply-category'),
                      onPressed: onApplyCategory,
                      child: const Text('Appliquer'),
                    ),
            ),
            if (s.keywords.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 30),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final k in s.keywords)
                      ActionChip(
                        key: ValueKey('ai-keyword-$k'),
                        label: Text(k),
                        avatar: const Icon(Icons.add_rounded, size: 16),
                        onPressed: () => onKeyword(k),
                      ),
                  ],
                ),
              ),
          ] else if (analysisFailed)
            row(Icons.image_not_supported_outlined,
                Text('Objet non reconnu : choisis la catégorie toi-même.', style: text.bodyMedium))
          else
            row(Icons.add_photo_alternate_outlined,
                Text('Ajoute une photo : l\'IA reconnaîtra l\'objet et sa catégorie.', style: text.bodyMedium)),
          if (!isFree)
            row(
              Icons.sell_outlined,
              Text(
                advice == null
                    ? 'Prix conseillé : pas encore assez d\'articles comparables.'
                    : 'Prix conseillé : ${advice.label} '
                        '(${advice.basedOn} article${advice.basedOn > 1 ? 's' : ''} '
                        '${advice.similarTitles ? 'similaires' : 'de la catégorie'})',
                key: const Key('ai-price'),
                style: text.bodyMedium,
              ),
              action: advice == null
                  ? null
                  : TextButton(
                      key: const Key('ai-use-price'),
                      onPressed: onUsePrice,
                      child: Text('${advice.suggested.round()} DT'),
                    ),
            ),
          const SizedBox(height: 12),
          PillButton(
            key: const Key('ai-write'),
            label: 'Rédiger la description avec l\'IA',
            icon: Icons.auto_awesome_outlined,
            style: PillStyle.ghost,
            isLoading: writing,
            onPressed: online ? onWrite : null,
          ),
          if (!online)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('La rédaction par IA demande une connexion.', style: text.bodySmall),
            ),
        ],
      ),
    );
  }
}
