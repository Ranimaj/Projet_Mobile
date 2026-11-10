import 'dart:io';

import 'package:campusconnect/services/two_factor_mailer.dart';

/// Envoi factice du code de double authentification : garde les messages,
/// ou échoue comme sans réseau.
class FakeMailer implements TwoFactorMailer {
  bool configured = true;
  bool failing = false;
  final List<({String to, String subject, String body})> sent = [];

  @override
  bool get isConfigured => configured;

  @override
  Future<void> send({required String to, required String subject, required String body}) async {
    if (failing) throw const SocketException('Network is unreachable');
    sent.add((to: to, subject: subject, body: body));
  }

  /// Le code du dernier email (le seul nombre à 6 chiffres du texte).
  String get lastCode => RegExp(r'\b\d{6}\b').firstMatch(sent.last.body)!.group(0)!;
}
