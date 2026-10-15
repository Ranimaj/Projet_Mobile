import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Notifications push (BF12) — annonces urgentes, nouveau message,
/// mise à jour du statut d'une candidature, rappel d'événement.
/// Les annonces officielles peuvent cibler un segment d'utilisateurs
/// (filière/année) via des topics Firebase Messaging — fonctionnalité
/// avancée du module Annonces.
class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  Future<void> initialize() async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('Notification reçue: ${message.notification?.title}');
    });
  }

  Future<String?> getDeviceToken() => _messaging.getToken();

  /// S'abonne à un topic de segmentation, ex. "major_genie-info" ou
  /// "year_3eme-annee", pour recevoir uniquement les annonces ciblées.
  Future<void> subscribeToSegment(String major, String year) async {
    await _messaging.subscribeToTopic('major_${_slug(major)}');
    await _messaging.subscribeToTopic('year_${_slug(year)}');
  }

  Future<void> unsubscribeFromSegment(String major, String year) async {
    await _messaging.unsubscribeFromTopic('major_${_slug(major)}');
    await _messaging.unsubscribeFromTopic('year_${_slug(year)}');
  }

  String _slug(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
}
