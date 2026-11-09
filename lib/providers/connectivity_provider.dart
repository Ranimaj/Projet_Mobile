import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/utils/connectivity_service.dart';

/// État du réseau pour toute l'app. Les données sont sur le téléphone et
/// restent disponibles hors-ligne ; seuls les services web (assistant IA,
/// cartes, météo, itinéraires) ont besoin du réseau.
class ConnectivityProvider extends ChangeNotifier {
  ConnectivityProvider({ConnectivityService? service}) : _service = service ?? ConnectivityService() {
    _init();
  }

  final ConnectivityService _service;
  StreamSubscription<bool>? _sub;

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  Future<void> _init() async {
    try {
      _isOnline = await _service.isOnline;
      notifyListeners();
      _sub = _service.onStatusChange.listen((online) {
        _isOnline = online;
        notifyListeners();
      });
    } catch (_) {
      // Plugin indisponible (tests) : on reste « en ligne ».
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
