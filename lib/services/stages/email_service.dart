import 'dart:async';
import 'dart:convert';

import 'package:mailer/mailer.dart' as mail;
import 'package:mailer/smtp_server.dart';

import '../../core/config/app_config.dart';
import '../../core/constants/app_constants.dart';
import '../../models/job_offer_model.dart';
import '../../models/stage_records.dart';
import '../local_store.dart';
import 'db_changes.dart';

/// File d'envoi des emails, stockée dans SQLite et envoyée en SMTP Gmail.
class EmailService {
  EmailService(this._store, this._changes, AppConfig config, {SmtpServer? server, String? from})
      : _server = server ?? (config.smtpConfigured ? gmail(config.smtpUser, config.smtpAppPassword) : null),
        _from = from ?? config.smtpUser;

  static const int maxAttempts = 5;
  static const Duration _timeout = Duration(seconds: 20);
  static const _emails = AppConstants.stageEmailsCollection;

  final LocalStore _store;
  final DbChanges _changes;
  final SmtpServer? _server;
  final String _from;

  /// Sérialise les envois pour ne jamais envoyer deux fois le même email.
  Future<void> _running = Future.value();

  bool get isConfigured => _server != null;

  /// Écrit l'email dans la file avant de rendre la main.
  Future<String> enqueue(ApplicationModel app, ApplicationStatus status, String note) async {
    final id = LocalStore.newId();
    final content = EmailTemplates.forStatus(app, status, note);
    // Les comptes de démonstration ont des adresses réalistes : aucun envoi réel.
    final demo = app.candidateId.startsWith('demo-');
    await _store.set(_emails, id, {
      'applicationId': app.id,
      'recipient': app.studentEmail,
      'subject': content.subject,
      'body': content.body,
      'status': (demo ? EmailStatus.skipped : EmailStatus.pending).name,
      'attempts': 0,
      'error': demo ? 'Compte de démonstration : aucun envoi réel' : '',
      'createdAt': DateTime.now(),
    });
    return id;
  }

  /// Tente d'envoyer tout ce qui attend. Sans SMTP configuré, la file est conservée.
  Future<void> flush() {
    final run = _running.then((_) => _flushOnce());
    _running = run.catchError((_) {});
    return run;
  }

  List<EmailRecord> _sorted(bool Function(Map<String, dynamic>) test) => [
        for (final d in _store.where(_emails, test)) EmailRecord.fromMap(d.id, d.data),
      ];

  Future<void> _flushOnce() async {
    final server = _server;
    if (server == null) return;
    final waiting = _sorted((d) => (d['status'] == EmailStatus.pending.name || d['status'] == EmailStatus.failed.name) && (d['attempts'] ?? 0) < maxAttempts)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final email in waiting) {
      await _sendOne(server, email);
    }
    if (waiting.isNotEmpty) _changes.bump();
  }

  Future<void> _sendOne(SmtpServer server, EmailRecord email) async {
    final message = mail.Message()
      ..from = mail.Address(_from, 'CampusConnect')
      ..recipients.add(email.recipient)
      ..subject = email.subject.replaceAll(RegExp(r'[\r\n]+'), ' ')
      ..text = email.body
      ..html = EmailTemplates.toHtml(email.body);
    try {
      await mail.send(message, server, timeout: _timeout);
      await _store.update(_emails, email.id, {
        'status': EmailStatus.sent.name,
        'attempts': email.attempts + 1,
        'error': '',
        'sentAt': DateTime.now(),
      });
    } on Exception catch (e) {
      await _store.update(_emails, email.id, {
        'status': EmailStatus.failed.name,
        'attempts': email.attempts + 1,
        'error': e.toString(),
      });
    }
  }

  /// Renvoi manuel depuis l'admin : remet le compteur d'essais à zéro.
  Future<void> retry(String id) async {
    await _store.update(_emails, id, {'status': EmailStatus.pending.name, 'attempts': 0, 'error': ''});
    _changes.bump();
    await flush();
  }

  Future<EmailStatus> statusOf(String id) async =>
      EmailRecord.fromMap(id, _store.get(_emails, id)!).status;

  Future<List<EmailRecord>> all() async => _sorted((_) => true)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
}

class EmailContent {
  const EmailContent(this.subject, this.body);

  final String subject;
  final String body;
}

class EmailTemplates {
  EmailTemplates._();

  static EmailContent forStatus(ApplicationModel app, ApplicationStatus status, String note) {
    final offer = '« ${app.jobTitle} » chez ${app.companyName}';
    final (subject, sentence) = switch (status) {
      ApplicationStatus.pending => (
          'Candidature reçue : ${app.jobTitle}',
          'Votre candidature à l\'offre $offer a bien été reçue. Elle est en attente d\'examen par le recruteur.'
        ),
      ApplicationStatus.hrInterview => (
          'Entretien RH : ${app.jobTitle}',
          'Bonne nouvelle : votre candidature à l\'offre $offer est retenue pour un entretien RH.'
        ),
      ApplicationStatus.technicalInterview => (
          'Entretien technique : ${app.jobTitle}',
          'Félicitations : vous avez passé l\'entretien RH pour l\'offre $offer. Vous êtes invité(e) à un entretien technique.'
        ),
      ApplicationStatus.accepted => (
          'Candidature acceptée : ${app.jobTitle}',
          'Félicitations : votre candidature à l\'offre $offer est acceptée.'
        ),
      ApplicationStatus.rejected => (
          'Réponse à votre candidature : ${app.jobTitle}',
          'Nous vous remercions de l\'intérêt porté à l\'offre $offer. Votre candidature n\'a malheureusement pas été retenue.'
        ),
    };
    final buffer = StringBuffer('Bonjour ${app.studentName},\n\n$sentence\n');
    if (note.isNotEmpty) buffer.write('\nMessage du recruteur :\n$note\n');
    buffer.write('\nVous pouvez suivre votre candidature dans l\'application CampusConnect.\n\nL\'équipe CampusConnect');
    return EmailContent(subject, buffer.toString());
  }

  static String toHtml(String text) {
    final escaped = const HtmlEscape().convert(text).replaceAll('\n', '<br>');
    return '<div style="font-family:Arial,sans-serif;font-size:15px;line-height:1.5;color:#1C1A33">$escaped</div>';
  }
}
