import 'package:flutter/material.dart';
import '../core/theme/app_tokens.dart';

/// Compact value + label tile on [AppTokens.surfaceMuted] (profile
/// counters, dashboards).
class StatTile extends StatelessWidget {
  final String value;
  final String label;
  final Color? valueColor;

  const StatTile({super.key, required this.value, required this.label, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final theme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: t.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.headlineMedium!.copyWith(color: valueColor ?? t.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: theme.labelMedium),
        ],
      ),
    );
  }
}
