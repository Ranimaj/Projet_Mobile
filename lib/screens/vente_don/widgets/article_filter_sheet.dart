import 'package:flutter/material.dart';

import '../../../core/constants/layout.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/article_search.dart';
import '../../../widgets/filter_chip_pill.dart';
import '../../../widgets/pill_button.dart';

/// Rayons proposés pour le filtre de distance (km).
const List<double> kDistanceChoices = [1, 3, 5, 10, 25];

/// Borne haute du curseur de prix : le prix le plus élevé arrondi à la
/// dizaine supérieure, au moins 100 DT.
double priceSliderMax(double highestPrice) {
  final top = highestPrice < 100 ? 100.0 : highestPrice;
  return (top / 10).ceil() * 10.0;
}

/// Feuille « Filtres » : tri, fourchette de prix, dons uniquement et rayon.
/// Renvoie les nouveaux filtres, ou null si la feuille est fermée sans valider.
Future<ArticleFilters?> showArticleFilterSheet(
  BuildContext context, {
  required ArticleFilters current,
  required double highestPrice,
  required bool hasPosition,
  required Future<bool> Function() onLocate,
}) {
  return showModalBottomSheet<ArticleFilters>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => ArticleFilterSheet(
      current: current,
      highestPrice: highestPrice,
      hasPosition: hasPosition,
      onLocate: onLocate,
    ),
  );
}

class ArticleFilterSheet extends StatefulWidget {
  final ArticleFilters current;
  final double highestPrice;
  final bool hasPosition;
  final Future<bool> Function() onLocate;

  const ArticleFilterSheet({
    super.key,
    required this.current,
    required this.highestPrice,
    required this.hasPosition,
    required this.onLocate,
  });

  @override
  State<ArticleFilterSheet> createState() => _ArticleFilterSheetState();
}

class _ArticleFilterSheetState extends State<ArticleFilterSheet> {
  late ArticleFilters _f = widget.current;
  late bool _hasPosition = widget.hasPosition;
  bool _locating = false;
  late final double _max = priceSliderMax(widget.highestPrice);

  RangeValues get _range => RangeValues(
        (_f.minPrice ?? 0).clamp(0, _max).toDouble(),
        (_f.maxPrice ?? _max).clamp(0, _max).toDouble(),
      );

  void _setRange(RangeValues v) {
    setState(() {
      if (v.start <= 0 && v.end >= _max) {
        _f = _f.copyWith(clearPrice: true);
      } else {
        _f = ArticleFilters(
          query: _f.query,
          category: _f.category,
          freeOnly: _f.freeOnly,
          minPrice: v.start <= 0 ? null : v.start,
          maxPrice: v.end >= _max ? null : v.end,
          maxDistanceKm: _f.maxDistanceKm,
          sort: _f.sort,
        );
      }
    });
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    final ok = await widget.onLocate();
    if (!mounted) return;
    setState(() {
      _locating = false;
      _hasPosition = ok;
    });
  }

  String _rangeLabel() {
    if (!_f.hasPriceRange) return 'Tous les prix';
    final r = _range;
    return '${r.start.round()} – ${r.end.round()} DT${r.end >= _max ? ' et plus' : ''}';
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final r = _range;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(kPagePadding, 0, kPagePadding, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Filtres', style: text.headlineMedium),
            const SizedBox(height: 16),
            _section(context, 'Trier par', [
              Wrap(
                spacing: 8,
                children: [
                  for (final s in ArticleSort.values)
                    FilterChipPill(
                      key: ValueKey('sort-${s.name}'),
                      label: s.label,
                      selected: _f.sort == s,
                      onTap: () => setState(() => _f = _f.copyWith(sort: s)),
                    ),
                ],
              ),
            ]),
            _section(context, 'Prix', [
              Text(_rangeLabel(), key: const Key('price-label'), style: text.bodyMedium),
              RangeSlider(
                key: const Key('price-slider'),
                values: r,
                min: 0,
                max: _max,
                divisions: (_max / 5).round(),
                labels: RangeLabels('${r.start.round()} DT', '${r.end.round()} DT'),
                onChanged: _f.freeOnly ? null : _setRange,
              ),
              SwitchListTile(
                key: const Key('free-only'),
                contentPadding: EdgeInsets.zero,
                title: Text('Dons gratuits uniquement', style: text.bodyLarge),
                value: _f.freeOnly,
                onChanged: (v) => setState(() => _f = _f.copyWith(freeOnly: v)),
              ),
            ]),
            _section(context, 'Distance', [
              if (!_hasPosition) ...[
                Text(
                  'Ta position sert à afficher les objets proches de toi. Elle n\'est jamais publiée.',
                  style: text.bodyMedium,
                ),
                const SizedBox(height: 10),
                PillButton(
                  key: const Key('locate'),
                  label: 'Utiliser ma position',
                  icon: Icons.my_location_rounded,
                  style: PillStyle.ghost,
                  isLoading: _locating,
                  onPressed: _locate,
                ),
              ] else
                Wrap(
                  spacing: 8,
                  children: [
                    FilterChipPill(
                      key: const ValueKey('distance-any'),
                      label: 'Partout',
                      selected: _f.maxDistanceKm == null,
                      onTap: () => setState(() => _f = _f.copyWith(clearDistance: true)),
                    ),
                    for (final km in kDistanceChoices)
                      FilterChipPill(
                        key: ValueKey('distance-${km.round()}'),
                        label: '${km.round()} km',
                        selected: _f.maxDistanceKm == km,
                        onTap: () => setState(() => _f = _f.copyWith(maxDistanceKm: km)),
                      ),
                  ],
                ),
              if (_f.sort == ArticleSort.nearest && !_hasPosition) ...[
                const SizedBox(height: 8),
                Text('Sans ta position, « Plus proches » trie par date.',
                    style: text.bodySmall?.copyWith(color: t.warning)),
              ],
            ]),
            Row(
              children: [
                Expanded(
                  child: PillButton(
                    key: const Key('reset-filters'),
                    label: 'Réinitialiser',
                    style: PillStyle.ghost,
                    onPressed: () => Navigator.of(context).pop(ArticleFilters(query: _f.query)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PillButton(
                    key: const Key('apply-filters'),
                    label: 'Appliquer',
                    onPressed: () => Navigator.of(context).pop(_f),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
