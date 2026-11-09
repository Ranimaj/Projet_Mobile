import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/utils/fr_dates.dart';
import '../../models/device_session.dart';
import '../../providers/auth_provider.dart';
import '../../services/device_session_service.dart';
import '../../widgets/auth/auth_feedback.dart';
import '../../widgets/setting_row.dart';
import '../../widgets/status_chip.dart';

IconData deviceIcon(String platform) => switch (platform) {
      'ios' || 'android' => Icons.smartphone_rounded,
      'macos' || 'windows' || 'linux' => Icons.laptop_mac_rounded,
      _ => Icons.devices_other_rounded,
    };

/// Gestion des Utilisateurs — « Mes appareils » : sessions ouvertes,
/// fermeture à distance, appareils de confiance et historique des connexions.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late final AuthProvider _auth = context.read<AuthProvider>();
  late final DeviceSessionService? _service = _auth.deviceSessions;
  late final String? _uid = _auth.currentUser?.id;
  late final Future<DeviceInfo>? _me = _service?.currentDevice();
  late final Stream<List<DeviceSession>>? _devices =
      _uid == null ? null : _service?.watchDevices(_uid);
  late final Stream<List<LoginRecord>>? _logins = _uid == null ? null : _service?.watchLogins(_uid);

  Future<void> _act(Future<void> Function() action, String done) async {
    try {
      await action();
      if (mounted) showAuthSnack(context, done, isError: false);
    } catch (_) {
      if (mounted) showAuthSnack(context, 'Action impossible pour le moment. Réessaie.');
    }
  }

  Future<bool> _confirm(String title, String body, String confirm) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(
            key: const Key('confirm-action'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirm),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _revoke(DeviceSession d) async {
    if (!await _confirm('Déconnecter ${d.name} ?',
        'La session sera fermée sur cet appareil dès qu\'il sera en ligne.', 'Déconnecter')) {
      return;
    }
    await _act(() => _service!.revoke(_uid!, d.id), '${d.name} sera déconnecté.');
  }

  Future<void> _revokeOthers() async {
    if (!await _confirm('Déconnecter les autres appareils ?',
        'Toutes les sessions sauf celle-ci seront fermées. Si tu penses que ton compte est piraté, '
            'change aussi ton mot de passe.',
        'Tout déconnecter')) {
      return;
    }
    await _act(() => _service!.revokeOthers(_uid!), 'Les autres appareils seront déconnectés.');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final service = _service;
    final devices = _devices;
    if (service == null || devices == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mes appareils')),
        body: const Center(child: Text('Indisponible pour le moment.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Mes appareils')),
      body: FutureBuilder<DeviceInfo>(
        future: _me,
        builder: (context, me) => StreamBuilder<List<DeviceSession>>(
          stream: devices,
          builder: (context, snap) {
            if (snap.hasError) {
              return const Center(child: Text('Impossible de charger tes appareils.'));
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final myId = me.data?.id;
            final all = snap.data!;
            final active = [
              ...all.where((d) => d.id == myId),
              ...all.where((d) => d.id != myId && d.isActive),
            ];
            final past = all.where((d) => d.id != myId && !d.isActive).toList();
            final othersActive = active.any((d) => d.id != myId);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                SettingGroup(
                  title: 'Connectés',
                  children: [
                    for (final d in active)
                      _DeviceTile(
                        device: d,
                        isThisDevice: d.id == myId,
                        onRevoke: () => _revoke(d),
                        onApprove: () => _act(() => service.setTrusted(_uid!, d.id, true), '${d.name} est approuvé.'),
                        onUntrust: () =>
                            _act(() => service.setTrusted(_uid!, d.id, false), '${d.name} n\'est plus de confiance.'),
                        onAcknowledge: () => _act(() => service.acknowledge(_uid!, d.id), 'Merci, c\'est noté.'),
                      ),
                  ],
                ),
                if (othersActive) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('revoke-others'),
                    onPressed: _revokeOthers,
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Déconnecter tous les autres appareils'),
                  ),
                ],
                if (past.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  SettingGroup(
                    title: 'Déconnectés',
                    children: [
                      for (final d in past)
                        SettingRow(
                          icon: deviceIcon(d.platform),
                          title: d.name,
                          subtitle: [
                            if (d.location != null) d.location!,
                            'Dernière connexion le ${FrDates.shortDateTime(d.lastLoginAt)}',
                          ].join(' · '),
                          trailing: StatusChip(
                            label: d.revoked ? 'Fermée à distance' : 'Déconnecté',
                            style: StatusChipStyle.neutral,
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                Text('Historique des connexions', style: text.titleSmall),
                const SizedBox(height: 8),
                _LoginHistory(stream: _logins!),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final DeviceSession device;
  final bool isThisDevice;
  final VoidCallback onRevoke;
  final VoidCallback onApprove;
  final VoidCallback onUntrust;
  final VoidCallback onAcknowledge;

  const _DeviceTile({
    required this.device,
    required this.isThisDevice,
    required this.onRevoke,
    required this.onApprove,
    required this.onUntrust,
    required this.onAcknowledge,
  });

  @override
  Widget build(BuildContext context) {
    final d = device;
    final chip = isThisDevice
        ? const StatusChip(label: 'Cet appareil', style: StatusChipStyle.success)
        : d.alertPending
            ? const StatusChip(label: 'Nouveau', style: StatusChipStyle.warning)
            : !d.trusted
                ? const StatusChip(label: 'À approuver', style: StatusChipStyle.warning)
                : null;
    return SettingRow(
      key: Key('device-${d.id}'),
      icon: deviceIcon(d.platform),
      title: d.name,
      subtitle: [
        if (d.location != null) d.location!,
        isThisDevice ? 'Connecté depuis le ${FrDates.shortDateTime(d.lastLoginAt)}' : 'Connexion le ${FrDates.shortDateTime(d.lastLoginAt)}',
      ].join(' · '),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (chip != null) chip,
          if (!isThisDevice)
            PopupMenuButton<String>(
              key: Key('device-menu-${d.id}'),
              tooltip: 'Actions',
              child: const SizedBox.square(dimension: 48, child: Icon(Icons.more_vert_rounded)),
              onSelected: (v) => switch (v) {
                'ack' => onAcknowledge(),
                'approve' => onApprove(),
                'untrust' => onUntrust(),
                _ => onRevoke(),
              },
              itemBuilder: (_) => [
                if (d.alertPending) const PopupMenuItem(value: 'ack', child: Text('C\'est bien moi')),
                if (!d.trusted) const PopupMenuItem(value: 'approve', child: Text('Approuver cet appareil')),
                if (d.trusted) const PopupMenuItem(value: 'untrust', child: Text('Ne plus faire confiance')),
                const PopupMenuItem(value: 'revoke', child: Text('Déconnecter')),
              ],
            ),
        ],
      ),
    );
  }
}

class _LoginHistory extends StatelessWidget {
  final Stream<List<LoginRecord>> stream;
  const _LoginHistory({required this.stream});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    return StreamBuilder<List<LoginRecord>>(
      stream: stream,
      builder: (context, snap) {
        final logins = snap.data ?? const [];
        if (logins.isEmpty) {
          return Text('Aucune connexion enregistrée.', style: text.bodyMedium?.copyWith(color: t.textSecondary));
        }
        return Column(
          children: [
            for (final l in logins)
              ListTile(
                key: Key('login-${l.id}'),
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                leading: Icon(l.newDevice ? Icons.fiber_new_rounded : Icons.login_rounded,
                    color: l.newDevice ? t.warning : t.textSecondary),
                title: Text(l.deviceName),
                subtitle: Text([FrDates.shortDateTime(l.at), if (l.location != null) l.location!].join(' · '),
                    style: text.bodyMedium?.copyWith(color: t.textSecondary)),
              ),
          ],
        );
      },
    );
  }
}
