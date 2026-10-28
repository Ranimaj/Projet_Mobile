import 'package:flutter/material.dart';
import 'status_chip.dart';

/// Synchronisation state: up to date, pending actions, or offline.
class SyncChip extends StatelessWidget {
  final bool online;
  final int pending;

  const SyncChip({super.key, required this.online, required this.pending});

  @override
  Widget build(BuildContext context) {
    if (!online) {
      return const StatusChip(
          label: 'Hors ligne',
          style: StatusChipStyle.warning,
          icon: Icons.wifi_off_rounded);
    }
    if (pending > 0) {
      return StatusChip(
          label: '$pending en attente',
          style: StatusChipStyle.warning,
          icon: Icons.sync_rounded);
    }
    return const StatusChip(
        label: 'À jour',
        style: StatusChipStyle.success,
        icon: Icons.check_circle_rounded);
  }
}
