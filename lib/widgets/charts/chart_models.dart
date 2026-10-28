import 'package:equatable/equatable.dart';
import 'package:flutter/painting.dart';

/// One point of a time series (x label + value).
class ChartPoint extends Equatable {
  const ChartPoint({required this.label, required this.value});

  final String label;
  final double value;

  @override
  List<Object?> get props => [label, value];
}

/// One slice of a donut chart.
class ChartSlice extends Equatable {
  const ChartSlice({required this.label, required this.value, required this.color});

  final String label;
  final double value;
  final Color color;

  @override
  List<Object?> get props => [label, value, color];
}

/// One row of a horizontal bar chart.
class ChartBar extends Equatable {
  const ChartBar({required this.label, required this.value, required this.color});

  final String label;
  final double value;
  final Color color;

  @override
  List<Object?> get props => [label, value, color];
}
