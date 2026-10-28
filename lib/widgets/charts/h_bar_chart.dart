import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import 'chart_empty.dart';
import 'chart_models.dart';

/// Horizontal bars: `label | bar (width proportional to value) | value`.
class HBarChart extends StatelessWidget {
  const HBarChart({
    super.key,
    required this.bars,
    this.barHeight = 12,
    this.emptyText = 'Pas encore de données',
  });

  final List<ChartBar> bars;
  final double barHeight;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (bars.isEmpty) return ChartEmpty(text: emptyText);
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final maxValue = bars.map((b) => b.value).reduce(math.max);
    final max = maxValue <= 0 ? 1.0 : maxValue;
    final duration = chartDuration(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final b in bars)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 84,
                  child: Text(b.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.labelMedium),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) => Stack(
                      children: [
                        Container(
                          height: barHeight,
                          decoration: BoxDecoration(
                            color: t.surfaceMuted,
                            borderRadius: BorderRadius.circular(barHeight / 2),
                          ),
                        ),
                        AnimatedContainer(
                          key: const Key('hbar-fill'),
                          duration: duration,
                          width: c.maxWidth * (b.value / max).clamp(0.0, 1.0),
                          height: barHeight,
                          decoration: BoxDecoration(
                            color: b.color,
                            borderRadius: BorderRadius.circular(barHeight / 2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Fixed width so every track has the same length.
                SizedBox(
                  width: 36,
                  child: Text(
                    '${b.value.round()}',
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    style: text.labelMedium!.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
