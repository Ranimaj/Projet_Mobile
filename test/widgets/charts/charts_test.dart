import 'package:campusconnect/widgets/charts/area_line_chart.dart';
import 'package:campusconnect/widgets/charts/chart_models.dart';
import 'package:campusconnect/widgets/charts/donut_chart.dart';
import 'package:campusconnect/widgets/charts/h_bar_chart.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_themed.dart';

const _points = [
  ChartPoint(label: 'L', value: 3),
  ChartPoint(label: 'M', value: 7),
  ChartPoint(label: 'M', value: 5),
  ChartPoint(label: 'J', value: 9),
];
const _slices = [
  ChartSlice(label: 'Vente', value: 60, color: Colors.orange),
  ChartSlice(label: 'Don', value: 40, color: Colors.green),
];
const _bars = [
  ChartBar(label: 'Alpha', value: 10, color: Colors.orange),
  ChartBar(label: 'Beta', value: 5, color: Colors.green),
  ChartBar(label: 'Gamma', value: 0, color: Colors.blue),
];

void main() {
  test('models compare by value', () {
    expect(const ChartPoint(label: 'a', value: 1), const ChartPoint(label: 'a', value: 1));
    expect(const ChartPoint(label: 'a', value: 1).hashCode, const ChartPoint(label: 'a', value: 1).hashCode);
  });

  for (final b in Brightness.values) {
    testWidgets('AreaLineChart renders a LineChart ($b)', (t) async {
      await pumpThemed(t, const AreaLineChart(points: _points), brightness: b);
      expect(find.byType(LineChart), findsOneWidget);
      expectNoSmallText(t);
    });
    testWidgets('AreaLineChart empty shows emptyText ($b)', (t) async {
      await pumpThemed(t, const AreaLineChart(points: []), brightness: b);
      expect(find.text('Pas encore de données'), findsOneWidget);
      expect(find.byType(LineChart), findsNothing);
    });
    testWidgets('DonutChart renders PieChart and legend ($b)', (t) async {
      await pumpThemed(t, const DonutChart(slices: _slices, centerLabel: '100'), brightness: b);
      expect(find.byType(PieChart), findsOneWidget);
      expect(find.text('Vente  60%'), findsOneWidget);
      expect(find.text('Don  40%'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expectNoSmallText(t);
    });
    testWidgets('DonutChart empty shows emptyText ($b)', (t) async {
      await pumpThemed(t, const DonutChart(slices: []), brightness: b);
      expect(find.text('Pas encore de données'), findsOneWidget);
      expect(find.byType(PieChart), findsNothing);
    });
    testWidgets('HBarChart renders three rows ($b)', (t) async {
      await pumpThemed(t, const SizedBox(width: 360, child: HBarChart(bars: _bars)), brightness: b);
      for (final l in ['Alpha', 'Beta', 'Gamma']) {
        expect(find.text(l), findsOneWidget);
      }
      expect(find.byKey(const Key('hbar-fill')), findsNWidgets(3));
      expectNoSmallText(t);
    });
    testWidgets('HBarChart empty shows emptyText ($b)', (t) async {
      await pumpThemed(t, const HBarChart(bars: []), brightness: b);
      expect(find.text('Pas encore de données'), findsOneWidget);
    });
  }

  testWidgets('AreaLineChart curve does not overshoot on sparse series', (t) async {
    const sparse = [
      ChartPoint(label: 'a', value: 0),
      ChartPoint(label: 'b', value: 10),
      ChartPoint(label: 'c', value: 0),
      ChartPoint(label: 'd', value: 0),
      ChartPoint(label: 'e', value: 8),
    ];
    await pumpThemed(t, const AreaLineChart(points: sparse));
    final chart = t.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineBarsData.single.preventCurveOverShooting, isTrue);
  });

  testWidgets('HBarChart widths are proportional to value', (t) async {
    await pumpThemed(t, const SizedBox(width: 360, child: HBarChart(bars: _bars)));
    await t.pumpAndSettle();
    final w = find.byKey(const Key('hbar-fill')).evaluate().map((e) => (e.renderObject! as RenderBox).size.width).toList();
    expect(w[1], closeTo(w[0] / 2, 0.5));
    expect(w[2], 0);
  });
}
