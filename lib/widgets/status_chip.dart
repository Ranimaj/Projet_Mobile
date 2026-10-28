import 'package:flutter/material.dart';
import '../core/theme/app_tokens.dart';

enum StatusChipStyle { soft, success, warning, danger, neutral, onPhoto }

/// Small rounded status label (Gratuit, Réservé, Inscrit…).
class StatusChip extends StatelessWidget {
  final String label;
  final StatusChipStyle style;
  final IconData? icon;

  const StatusChip({super.key, required this.label, this.style = StatusChipStyle.soft, this.icon});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final (bg, fg) = switch (style) {
      StatusChipStyle.soft => (t.primarySoft, t.onPrimarySoft),
      StatusChipStyle.success => (t.successSoft, t.success),
      StatusChipStyle.warning => (t.warningSoft, t.warning),
      StatusChipStyle.danger => (t.dangerSoft, t.danger),
      StatusChipStyle.neutral => (t.surfaceMuted, t.textSecondary),
      StatusChipStyle.onPhoto => (Colors.white, AppTokens.light.textPrimary),
    };
    return StatusChipBody(label: label, background: bg, foreground: fg, icon: icon);
  }
}

/// Shared rendering of a chip with explicit colours (used by [StatusChip] and
/// by the explicit-colour constructor of `StatusBadge`).
class StatusChipBody extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;
  final IconData? icon;

  const StatusChipBody({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('chip-fill'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall!.copyWith(color: foreground, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
