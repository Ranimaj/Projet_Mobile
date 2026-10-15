import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Surveille l'état du réseau et expose un flux booléen "en ligne / hors-ligne".
/// Utilisé par [ConnectivityProvider] pour piloter le bandeau offline
/// et déclencher la synchronisation de la file d'attente locale.
class ConnectivityService {
  final Connectivity _connectivity = Connectivity();

  Stream<bool> get onStatusChange => _connectivity.onConnectivityChanged.map(
        (results) => !results.contains(ConnectivityResult.none),
      );

  Future<bool> get isOnline async {
    final result = await _connectivity.checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }
}
