import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mailer/smtp_server.dart';

/// Serveur SMTP minimal qui enregistre les messages reçus.
class FakeSmtp {
  FakeSmtp._(this._server);

  final ServerSocket _server;
  final List<String> messages = [];
  final List<String> recipients = [];

  /// Tant que vrai, chaque DATA est refusé (panne simulée).
  bool failing = false;

  int get port => _server.port;

  SmtpServer get config => SmtpServer('127.0.0.1', port: port, allowInsecure: true, ignoreBadCertificate: true);

  static Future<FakeSmtp> start() async {
    final smtp = FakeSmtp._(await ServerSocket.bind(InternetAddress.loopbackIPv4, 0));
    smtp._server.listen(smtp._handle);
    return smtp;
  }

  void _handle(Socket socket) {
    socket.write('220 fake ESMTP\r\n');
    var inData = false;
    final buffer = StringBuffer();
    socket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      if (inData) {
        if (line == '.') {
          inData = false;
          messages.add(buffer.toString());
          buffer.clear();
          socket.write('250 OK\r\n');
        } else {
          buffer.writeln(line);
        }
        return;
      }
      final upper = line.toUpperCase();
      if (upper.startsWith('EHLO') || upper.startsWith('HELO')) {
        socket.write('250 fake\r\n');
      } else if (upper.startsWith('RCPT TO')) {
        recipients.add(line.substring(line.indexOf(':') + 1).trim());
        socket.write('250 OK\r\n');
      } else if (upper.startsWith('DATA')) {
        if (failing) {
          socket.write('554 refused\r\n');
        } else {
          inData = true;
          socket.write('354 go\r\n');
        }
      } else if (upper.startsWith('QUIT')) {
        socket.write('221 bye\r\n');
        unawaited(socket.close());
      } else {
        socket.write('250 OK\r\n');
      }
    }, onError: (_) {});
  }

  Future<void> stop() => _server.close();
}
