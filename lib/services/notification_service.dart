import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/segment_topics.dart';

/// Notification reçue pendant que l'app est au premier plan.
class PushEvent {
  final String? title;
  final String? body;
  final String? annonceId;
  const PushEvent({this.title, this.body, this.annonceId});
}

/// Notifications push (Firebase Cloud Messaging) — API dédiée du module
/// Gestion Annonces.
///
/// Ciblage par filière / année :
///  - chaque appareil s'abonne aux topics de SON profil
///    (`all_campus`, `major_<filière>`, `year_<n>`) — voir [syncTopics] ;
///  - à la publication d'une annonce, la Cloud Function (dossier
///    `functions/`) envoie le message aux topics ciblés par l'annonce.
class NotificationService {
  NotificationService._();
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;

  static const _topicsKey = 'annonce_push_topics';
  static const _enabledKey = 'annonce_push_enabled';

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;
  Box get _box => Hive.box(AppConstants.hiveUserBox);

  /// Faux si la boîte Hive n'est pas (encore) ouverte, ex. dans les tests
  /// d'écran : on retombe alors sur les valeurs par défaut.
  bool get _hasBox => Hive.isBoxOpen(AppConstants.hiveUserBox);

  bool _initialized = false;

  final _foreground = StreamController<PushEvent>.broadcast();

  /// Notifications reçues app ouverte (affichées en SnackBar par l'écran).
  Stream<PushEvent> get onForeground => _foreground.stream;

  /// Id de l'annonce à ouvrir après un clic sur une notification.
  final ValueNotifier<String?> openedAnnonceId = ValueNotifier<String?>(null);

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    FirebaseMessaging.onMessage.listen((message) {
      _foreground.add(PushEvent(
        title: message.notification?.title,
        body: message.notification?.body,
        annonceId: message.data['annonceId']?.toString(),
      ));
    });

    // Clic sur une notification (app en arrière-plan).
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpened);

    // Clic sur une notification (app fermée).
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _handleOpened(initial);
  }

  void _handleOpened(RemoteMessage message) {
    final id = message.data['annonceId']?.toString();
    if (id != null && id.isNotEmpty) openedAnnonceId.value = id;
  }

  Future<String?> getDeviceToken() => _messaging.getToken();

  // ---------------------------------------------------------------------
  // Préférence utilisateur : recevoir (ou non) les notifications d'annonces
  // ---------------------------------------------------------------------
  bool get pushEnabled =>
      !_hasBox || (_box.get(_enabledKey, defaultValue: true) as bool);

  Future<void> setPushEnabled(bool value) async {
    if (_hasBox) await _box.put(_enabledKey, value);
  }

  // ---------------------------------------------------------------------
  // Abonnement aux topics de segmentation
  // ---------------------------------------------------------------------
  Set<String> get _subscribed => !_hasBox
      ? <String>{}
      : Set<String>.from(
          (_box.get(_topicsKey, defaultValue: <dynamic>[]) as List).cast<String>());

  /// Aligne les abonnements de l'appareil sur le profil [major]/[year].
  /// N'abonne / désabonne que la différence (et mémorise l'état localement,
  /// donc un échec réseau est simplement rejoué au prochain appel).
  Future<void> syncTopics({String? major, String? year}) async {
    final wanted = pushEnabled ? SegmentTopics.forUser(major, year) : <String>{};
    await _applyTopics(wanted);
  }

  /// Désabonne tout (déconnexion).
  Future<void> clearTopics() => _applyTopics(<String>{});

  Future<void> _applyTopics(Set<String> wanted) async {
    final current = _subscribed;
    final next = <String>{...current};

    for (final topic in current.difference(wanted)) {
      try {
        await _messaging.unsubscribeFromTopic(topic);
        next.remove(topic);
      } catch (e) {
        debugPrint('Désabonnement $topic impossible: $e');
      }
    }
    for (final topic in wanted.difference(current)) {
      try {
        await _messaging.subscribeToTopic(topic);
        next.add(topic);
      } catch (e) {
        debugPrint('Abonnement $topic impossible: $e');
      }
    }
    if (_hasBox) await _box.put(_topicsKey, next.toList());
  }
}
