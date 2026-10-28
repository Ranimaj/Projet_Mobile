import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import 'chart_empty.dart';
import 'chart_models.dart';

/// Smooth line chart with a gradient area under the curve.
class AreaLineChart extends StatelessWidget {
  const AreaLineChart({
    super.key,
    required this.points,
    this.emptyText = 'Pas encore de données',
    this.tooltip,
    this.height = 160,
  });

  final List<ChartPoint> points;
  final String emptyText;
  final String Function(ChartPoint p)? tooltip;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return ChartEmpty(text: emptyText, height: height);
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final maxValue = points.map((p) => p.value).reduce(math.max);
    final maxY = maxValue <= 0 ? 1.0 : maxValue * 1.15;
    final step = math.max(1, points.length ~/ 5);
    final last = points.length - 1;

    return SizedBox(
      height: height,
      child: LineChart(
        duration: chartDuration(context),
        LineChartData(
          minX: 0,
          maxX: math.max(last, 1).toDouble(),
          minY: 0,
          maxY: maxY,
          borderData: FlBorderData(show: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY / 4,
            getDrawingHorizontalLine: (_) => FlLine(color: t.outline, strokeWidth: 1),
          ),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (value != i.toDouble() || i < 0 || i > last || i % step != 0) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(points[i].label, style: text.labelSmall),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => t.surface,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    tooltip?.call(points[s.spotIndex]) ?? '${points[s.spotIndex].value.round()}',
                    text.labelMedium!.copyWith(color: t.textPrimary, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].value)],
              isCurved: true,
              color: t.primary,
              barWidth: 2.5,
              dotData: FlDotData(
                show: true,
                checkToShowDot: (spot, _) => spot.x == last.toDouble(),
                getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                  radius: 4,
                  color: t.primary,
                  strokeWidth: 2,
                  strokeColor: t.surface,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [t.primary.withValues(alpha: 0.35), t.primary.withValues(alpha: 0)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
