import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/fr_dates.dart';
import '../../models/device_session.dart';
import '../../providers/auth_provider.dart';
import '../../services/device_session_service.dart';
import '../profile/change_password_screen.dart';

/// Surveille les appareils du compte pendant que l'app est ouverte : quand
/// une connexion arrive d'un **nouvel** appareil, une alerte demande
/// « C'est toi ? ». « Non » ferme cette session à distance et propose de
/// changer le mot de passe.
class NewDeviceAlert extends StatefulWidget {
  final Widget child;
  const NewDeviceAlert({super.key, required this.child});

  @override
  State<NewDeviceAlert> createState() => _NewDeviceAlertState();
}

class _NewDeviceAlertState extends State<NewDeviceAlert> {
  StreamSubscription<List<DeviceSession>>? _sub;
  DeviceSessionService? _service;
  String? _uid;
  String? _myId;
  final _shown = <String>{};
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final auth = context.read<AuthProvider>();
    final service = auth.deviceSessions;
    final uid = auth.currentUser?.id;
    if (service == null || uid == null) return;
    try {
      _myId = (await service.currentDevice()).id;
    } catch (_) {
      return;
    }
    if (!mounted) return;
    _service = service;
    _uid = uid;
    _sub = service.watchDevices(uid).listen(_onDevices, onError: (Object _) {});
  }

  void _onDevices(List<DeviceSession> devices) {
    if (_open || !mounted) return;
    for (final d in devices) {
      if (d.id == _myId || !d.alertPending || !d.isActive || _shown.contains(d.id)) continue;
      _shown.add(d.id);
      _ask(d);
      return;
    }
  }

  Future<void> _ask(DeviceSession d) async {
    _open = true;
    final notMe = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        key: const Key('new-device-alert'),
        icon: const Icon(Icons.warning_amber_rounded),
        title: const Text('Nouvelle connexion'),
        content: Text(
          '${d.name}${d.location == null ? '' : ' · ${d.location}'}\n'
          'le ${FrDates.shortDateTime(d.lastLoginAt)}\n\n'
          'Est-ce bien toi ?',
        ),
        actions: [
          TextButton(
            key: const Key('new-device-not-me'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Non, déconnecter'),
          ),
          FilledButton(
            key: const Key('new-device-me'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Oui, c\'est moi'),
          ),
        ],
      ),
    );
    _open = false;
    final service = _service, uid = _uid;
    if (service == null || uid == null || !mounted) return;
    try {
      if (notMe == true) {
        await service.revoke(uid, d.id);
        if (!mounted) return;
        await _suggestPasswordChange();
      } else {
        await service.acknowledge(uid, d.id);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Action impossible. Va dans Profil › Mes appareils.')));
      }
    }
  }

  Future<void> _suggestPasswordChange() async {
    final auth = context.read<AuthProvider>();
    final change = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Appareil déconnecté'),
        content: Text(auth.hasPasswordProvider
            ? 'Quelqu\'un connaît sans doute ton mot de passe. Change-le maintenant et active la double '
                'authentification.'
            : 'Active la double authentification pour mieux protéger ton compte.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Plus tard')),
          if (auth.hasPasswordProvider)
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Changer le mot de passe'),
            ),
        ],
      ),
    );
    if (change == true && mounted) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ChangePasswordScreen()));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
