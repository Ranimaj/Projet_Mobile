import 'package:flutter/material.dart';
import 'status_chip.dart';

/// Status badge shared by the 4 modules; a thin wrapper over [StatusChip].
/// The explicit-colour constructor is kept for compatibility.
class StatusBadge extends StatelessWidget {
  final String label;
  final Color? background;
  final Color? foreground;
  final StatusChipStyle? _style;

  const StatusBadge({
    super.key,
    required this.label,
    required Color this.background,
    required Color this.foreground,
  }) : _style = null;

  const StatusBadge._styled(this.label, StatusChipStyle style)
      : _style = style,
        background = null,
        foreground = null;

  factory StatusBadge.success(String label) => StatusBadge._styled(label, StatusChipStyle.success);
  factory StatusBadge.warning(String label) => StatusBadge._styled(label, StatusChipStyle.warning);
  factory StatusBadge.info(String label) => StatusBadge._styled(label, StatusChipStyle.neutral);
  factory StatusBadge.danger(String label) => StatusBadge._styled(label, StatusChipStyle.danger);

  @override
  Widget build(BuildContext context) {
    final style = _style;
    if (style != null) return StatusChip(label: label, style: style);
    return StatusChipBody(label: label, background: background!, foreground: foreground!);
  }
}
