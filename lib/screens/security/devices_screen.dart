import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/utils/fr_dates.dart';
import '../../models/device_session.dart';
import '../../providers/auth_provider.dart';
import '../../services/device_session_service.dart';
import '../../widgets/setting_row.dart';
import '../../widgets/status_chip.dart';

IconData deviceIcon(String platform) => switch (platform) {
      'ios' || 'android' => Icons.smartphone_rounded,
      'macos' || 'windows' || 'linux' => Icons.laptop_mac_rounded,
      _ => Icons.devices_other_rounded,
    };

String platformLabel(String platform) => switch (platform) {
      'android' => 'Android',
      'ios' => 'iOS',
      'macos' => 'macOS',
      'windows' => 'Windows',
      'linux' => 'Linux',
      '' => 'Plateforme inconnue',
      _ => platform,
    };

/// Gestion des Utilisateurs — « Mes appareils » : ce téléphone et
/// l'historique des connexions du compte sur ce téléphone. Sans serveur,
/// l'app ne voit aucun autre appareil.
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
  late final Stream<DeviceSession?>? _device = _uid == null ? null : _service?.watchThisDevice(_uid);
  late final Stream<List<LoginRecord>>? _logins = _uid == null ? null : _service?.watchLogins(_uid);

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    if (_service == null || _uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mes appareils')),
        body: const Center(child: Text('Indisponible pour le moment.')),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Mes appareils')),
      body: FutureBuilder<DeviceInfo>(
        future: _me,
        builder: (context, me) => StreamBuilder<DeviceSession?>(
          stream: _device,
          builder: (context, device) => StreamBuilder<List<LoginRecord>>(
            stream: _logins,
            builder: (context, logins) {
              if (me.hasError || device.hasError || logins.hasError) {
                return const Center(child: Text('Impossible de charger tes appareils.'));
              }
              if (!me.hasData || !logins.hasData) return const Center(child: CircularProgressIndicator());
              final info = me.data!;
              final session = device.data;
              final name = session?.name ?? info.name;
              final platform = session?.platform ?? info.platform;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  SettingGroup(
                    title: 'Ce téléphone',
                    children: [
                      SettingRow(
                        key: const Key('this-device'),
                        icon: deviceIcon(platform),
                        title: name,
                        subtitle: [
                          platformLabel(platform),
                          if (session?.location != null) session!.location!,
                          if (session?.lastLoginAt != null)
                            'Connecté depuis le ${FrDates.shortDateTime(session!.lastLoginAt)}',
                        ].join(' · '),
                        trailing: const StatusChip(label: 'Cet appareil', style: StatusChipStyle.success),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    key: const Key('devices-local-note'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: t.surfaceMuted, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.lock_outline_rounded, size: 20, color: t.textSecondary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Ces informations restent sur ce téléphone : elles ne sont envoyées nulle part, '
                            'et les connexions faites sur un autre téléphone n\'apparaissent pas ici.',
                            style: text.bodyMedium?.copyWith(color: t.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Historique des connexions', style: text.titleSmall),
                  const SizedBox(height: 8),
                  _LoginHistory(logins: logins.data!),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LoginHistory extends StatelessWidget {
  final List<LoginRecord> logins;
  const _LoginHistory({required this.logins});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
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
  }
}
