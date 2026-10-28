import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'chart_empty.dart';
import 'chart_models.dart';

/// Donut chart with a legend (`label  percent%`) on its right.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.slices,
    this.centerLabel,
    this.size = 120,
    this.emptyText = 'Pas encore de données',
  });

  final List<ChartSlice> slices;
  final String? centerLabel;
  final double size;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<double>(0, (a, s) => a + s.value);
    if (slices.isEmpty || total == 0) return ChartEmpty(text: emptyText);
    final text = Theme.of(context).textTheme;

    return Row(
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                duration: chartDuration(context),
                PieChartData(
                  centerSpaceRadius: size * 0.32,
                  sectionsSpace: 2,
                  borderData: FlBorderData(show: false),
                  pieTouchData: PieTouchData(enabled: false),
                  sections: [
                    for (final s in slices)
                      PieChartSectionData(
                        value: s.value,
                        color: s.color,
                        radius: size * 0.18,
                        showTitle: false,
                      ),
                  ],
                ),
              ),
              if (centerLabel != null) Text(centerLabel!, style: text.titleMedium),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in slices)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(2)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${s.label}  ${(s.value / total * 100).round()}%',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelMedium,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
