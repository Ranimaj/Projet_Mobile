import 'package:flutter/material.dart';

/// Shared empty state of the chart wrappers.
class ChartEmpty extends StatelessWidget {
  const ChartEmpty({super.key, required this.text, this.height});

  final String text;
  final double? height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height ?? 80,
        child: Center(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      );
}

/// Animation duration for charts: at most 200 ms, none when animations are off.
Duration chartDuration(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 200);
