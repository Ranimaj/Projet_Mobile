import 'package:mailer/mailer.dart' as mail;
import 'package:mailer/smtp_server.dart';

import '../core/config/app_config.dart';
import 'stages/email_service.dart' show EmailTemplates;

/// Email du code de double authentification (le code n'est pas dans l'objet,
/// qui s'affiche dans les notifications).
class TwoFactorEmail {
  TwoFactorEmail._();

  static const String subject = 'Votre code de connexion CampusConnect';

  static String body({
    required String code,
    required String name,
    required DateTime expiresAt,
    required Duration validity,
  }) {
    final hello = name.trim().isEmpty ? 'Bonjour,' : 'Bonjour ${name.trim()},';
    final until = '${expiresAt.hour}h${expiresAt.minute.toString().padLeft(2, '0')}';
    return '$hello\n\n'
        'Votre code de connexion CampusConnect : $code\n\n'
        'Il est valable ${validity.inMinutes} minutes (jusqu\'à $until). Ne le communiquez à personne.\n\n'
        'Si vous n\'êtes pas à l\'origine de cette connexion, changez votre mot de passe.\n\n'
        'L\'équipe CampusConnect';
  }
}

/// Email du code de réinitialisation du mot de passe (le code n'est pas dans
/// l'objet).
class PasswordResetEmail {
  PasswordResetEmail._();

  static const String subject = 'Réinitialisation de votre mot de passe CampusConnect';

  static String body({
    required String code,
    required String name,
    required DateTime expiresAt,
    required Duration validity,
  }) {
    final hello = name.trim().isEmpty ? 'Bonjour,' : 'Bonjour ${name.trim()},';
    final until = '${expiresAt.hour}h${expiresAt.minute.toString().padLeft(2, '0')}';
    return '$hello\n\n'
        'Votre code pour choisir un nouveau mot de passe CampusConnect : $code\n\n'
        'Il est valable ${validity.inMinutes} minutes (jusqu\'à $until). Ne le communiquez à personne.\n\n'
        'Si vous n\'avez rien demandé, ignorez ce message : votre mot de passe ne change pas.\n\n'
        'L\'équipe CampusConnect';
  }
}

/// Envoi des codes par email (double authentification, mot de passe oublié).
abstract class TwoFactorMailer {
  /// `false` sans identifiants SMTP : le code reste affiché dans l'app.
  bool get isConfigured;

  /// Envoie le message tout de suite. Lève une exception si l'envoi échoue
  /// (pas de réseau, identifiants refusés...).
  Future<void> send({required String to, required String subject, required String body});
}

/// Même configuration que les emails du module Stage & Emploi
/// ([AppConfig.smtpUser], [AppConfig.smtpAppPassword], serveur Gmail), mais
/// sans file d'attente : un code qui expire en 5 minutes part tout de suite
/// ou pas du tout.
class SmtpTwoFactorMailer implements TwoFactorMailer {
  SmtpTwoFactorMailer({AppConfig config = const AppConfig(), SmtpServer? server, String? from})
      : _server = server ?? (config.smtpConfigured ? gmail(config.smtpUser, config.smtpAppPassword) : null),
        _from = from ?? config.smtpUser;

  static const Duration _timeout = Duration(seconds: 20);

  final SmtpServer? _server;
  final String _from;

  @override
  bool get isConfigured => _server != null;

  @override
  Future<void> send({required String to, required String subject, required String body}) async {
    final server = _server;
    if (server == null) throw StateError('SMTP non configuré');
    final message = mail.Message()
      ..from = mail.Address(_from, 'CampusConnect')
      ..recipients.add(to)
      ..subject = subject.replaceAll(RegExp(r'[\r\n]+'), ' ')
      ..text = body
      ..html = EmailTemplates.toHtml(body);
    await mail.send(message, server, timeout: _timeout);
  }
}
