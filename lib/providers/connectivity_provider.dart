import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/utils/connectivity_service.dart';
import '../core/utils/offline_queue_service.dart';

/// Pilote l'état réseau pour toute l'app : affichage du bandeau "mode
/// hors-ligne" (voir OfflineBanner), et déclenchement automatique de la
/// synchronisation de la file d'attente dès que la connexion revient (BNF3).
class ConnectivityProvider extends ChangeNotifier {
  final ConnectivityService _service = ConnectivityService();
  final OfflineQueueService queueService = OfflineQueueService();
  StreamSubscription<bool>? _sub;

  bool _isOnline = true;
  bool get isOnline => _isOnline;
  int get pendingActionsCount => queueService.pendingCount;

  ConnectivityProvider() {
    _init();
  }

  Future<void> _init() async {
    _isOnline = await _service.isOnline;
    notifyListeners();

    _sub = _service.onStatusChange.listen((online) async {
      final wasOffline = !_isOnline;
      _isOnline = online;
      notifyListeners();

      if (online && wasOffline) {
        await _syncPendingActions();
      }
    });
  }

  Future<void> _syncPendingActions() async {
    if (queueService.pendingCount == 0) return;
    await queueService.syncAll(FirebaseFirestore.instance);
    notifyListeners();
  }

  /// Permet de forcer une tentative de synchro manuelle (ex. pull-to-refresh).
  Future<void> retrySync() => _syncPendingActions();

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
