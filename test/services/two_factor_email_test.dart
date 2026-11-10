import 'dart:convert';
import 'dart:math';

import 'package:campusconnect/core/config/app_config.dart';
import 'package:campusconnect/core/constants/app_constants.dart';
import 'package:campusconnect/core/utils/auth_failure.dart';
import 'package:campusconnect/core/utils/password_hasher.dart';
import 'package:campusconnect/services/auth_service.dart';
import 'package:campusconnect/services/local_store.dart';
import 'package:campusconnect/services/two_factor_mailer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_smtp.dart';
import '../helpers/fake_two_factor_mailer.dart';
import '../helpers/local_db.dart';
import '../helpers/mocks.dart';

Matcher failsWith(String code, [Object? message]) => throwsA(isA<AuthFailure>()
    .having((f) => f.code, 'code', code)
    .having((f) => f.message, 'message', message ?? anything));

void main() {
  late LocalStore store;
  late FakeMailer mailer;
  late DateTime now;
  late AuthService service;

  AuthService build() => AuthService(
        store: store,
        storage: MockStorageService(),
        hasher: PasswordHasher(iterations: 1),
        random: Random(7),
        clock: () => now,
        mailer: mailer,
      );

  setUp(() async {
    await openTestDatabase();
    store = LocalStore();
    mailer = FakeMailer();
    now = DateTime(2026, 3, 1, 10);
    service = build();
  });

  tearDown(closeTestDatabase);

  /// Compte avec la double authentification, connecté par mot de passe : la
  /// connexion attend le code.
  Future<String> signInPending() async {
    final user = await service.registerWithEmail(email: 'amel@esprit.tn', password: 'secret123', fullName: 'Amel Test');
    await store.update(AppConstants.usersCollection, user.id, {
      'twoFactorEnabled': true,
      'isPhoneVerified': true,
      'phoneNumber': '+21620123456',
    });
    await service.signOut();
    await service.signInWithEmail('amel@esprit.tn', 'secret123');
    expect(service.twoFactorPending, isTrue);
    return user.id;
  }

  Map<String, dynamic>? stored(String uid) {
    final raw = store.getValue(AuthService.twoFactorEmailKey(uid));
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  String wrongCode() => mailer.lastCode == '000000' ? '111111' : '000000';

  group('envoi du code', () {
    test('a 6-digit code goes to the account address; only a salted hash is stored', () async {
      final uid = await signInPending();
      expect(service.twoFactorByEmail, isTrue);

      final sent = await service.sendTwoFactorEmail();

      expect(mailer.sent, hasLength(1));
      expect(mailer.sent.single.to, 'amel@esprit.tn');
      final code = mailer.lastCode;
      expect(code, matches(RegExp(r'^\d{6}$')));
      expect(sent.email, 'amel@esprit.tn');
      expect(sent.expiresAt, now.add(const Duration(minutes: 5)));
      expect(sent.resendIn, const Duration(seconds: 30));

      final raw = store.getValue(AuthService.twoFactorEmailKey(uid))!;
      expect(raw, isNot(contains(code)));
      final record = stored(uid)!;
      expect(record['hash'], isA<String>());
      expect(record['salt'], isA<String>());
      expect(record['failures'], 0);
      expect(DateTime.parse(record['expiresAt'] as String), now.add(AuthService.otpValidity));
    });

    test('the e-mail is short, in French, gives the expiry and keeps the code out of the subject', () async {
      await signInPending();
      await service.sendTwoFactorEmail();
      final email = mailer.sent.single;

      expect(email.subject, 'Votre code de connexion CampusConnect');
      expect(email.subject, isNot(contains(RegExp(r'\d'))));
      expect(email.body, startsWith('Bonjour Amel Test,'));
      expect(email.body, contains('Votre code de connexion CampusConnect : ${mailer.lastCode}'));
      expect(email.body, contains("Il est valable 5 minutes (jusqu'à 10h05)."));
      expect(email.body, endsWith("L'équipe CampusConnect"));
    });

    test('reopening the screen does not send another e-mail while the code is valid', () async {
      await signInPending();
      await service.sendTwoFactorEmail();
      now = now.add(const Duration(seconds: 10));

      final again = await service.sendTwoFactorEmail();

      expect(mailer.sent, hasLength(1));
      expect(again.resendIn, const Duration(seconds: 20));
    });

    test('nothing is sent without a pending two-factor sign-in', () async {
      await service.registerWithEmail(email: 'amel@esprit.tn', password: 'secret123', fullName: 'Amel Test');
      await expectLater(() => service.sendTwoFactorEmail(), failsWith('otp-not-sent'));
      expect(mailer.sent, isEmpty);
    });
  });

  group('vérification', () {
    test('the right code completes the sign-in and forgets the code', () async {
      final uid = await signInPending();
      await service.sendTwoFactorEmail();

      await service.verifyTwoFactorEmail(mailer.lastCode);

      expect(service.twoFactorPending, isFalse);
      expect(service.currentAccount?.uid, uid);
      expect(stored(uid), isNull);
    });

    test('the code expires after 5 minutes', () async {
      await signInPending();
      await service.sendTwoFactorEmail();
      final code = mailer.lastCode;

      now = now.add(AuthService.otpValidity);
      await expectLater(
        () => service.verifyTwoFactorEmail(code),
        failsWith('session-expired', 'Le code a expiré. Demandez-en un nouveau.'),
      );
      expect(service.twoFactorPending, isTrue);

      // Un nouveau code peut être demandé tout de suite.
      await service.sendTwoFactorEmail(resend: true);
      await service.verifyTwoFactorEmail(mailer.lastCode);
      expect(service.twoFactorPending, isFalse);
    });

    test('wrong codes are counted; the 5th locks for 5 minutes, then a new code works', () async {
      final uid = await signInPending();
      await service.sendTwoFactorEmail();
      final code = mailer.lastCode;
      final wrong = wrongCode();

      for (final left in [4, 3, 2]) {
        await expectLater(
          () => service.verifyTwoFactorEmail(wrong),
          failsWith('invalid-verification-code', 'Code incorrect. Encore $left essais.'),
        );
      }
      await expectLater(
        () => service.verifyTwoFactorEmail(wrong),
        failsWith('invalid-verification-code', 'Code incorrect. Dernier essai avant un blocage de 5 minutes.'),
      );
      expect(stored(uid)!['failures'], 4);
      await expectLater(
        () => service.verifyTwoFactorEmail(wrong),
        failsWith('otp-locked', "Trop d'essais. Nouvel essai possible dans 5 min."),
      );

      // Bloqué : même le bon code est refusé, et aucun email ne part.
      await expectLater(() => service.verifyTwoFactorEmail(code), failsWith('otp-locked'));
      now = now.add(const Duration(minutes: 2));
      await expectLater(
        () => service.sendTwoFactorEmail(resend: true),
        failsWith('otp-locked', "Trop d'essais. Nouvel essai possible dans 3 min."),
      );
      expect(mailer.sent, hasLength(1));
      expect(service.twoFactorPending, isTrue);

      now = now.add(const Duration(minutes: 3));
      await service.sendTwoFactorEmail(resend: true);
      expect(stored(uid)!['failures'], 0);
      await service.verifyTwoFactorEmail(mailer.lastCode);
      expect(service.twoFactorPending, isFalse);
    });

    test('a malformed code counts as a wrong one', () async {
      final uid = await signInPending();
      await service.sendTwoFactorEmail();
      await expectLater(() => service.verifyTwoFactorEmail('12ab'), failsWith('invalid-verification-code'));
      expect(stored(uid)!['failures'], 1);
    });
  });

  group('renvoi', () {
    test('allowed after 30 seconds; the new code replaces the old one', () async {
      await signInPending();
      await service.sendTwoFactorEmail();
      final first = mailer.lastCode;

      now = now.add(const Duration(seconds: 12));
      await expectLater(
        () => service.sendTwoFactorEmail(resend: true),
        failsWith('otp-cooldown', 'Patiente 18 s avant de demander un nouveau code.'),
      );
      expect(mailer.sent, hasLength(1));

      now = now.add(const Duration(seconds: 18));
      final sent = await service.sendTwoFactorEmail(resend: true);
      expect(mailer.sent, hasLength(2));
      expect(sent.resendIn, AuthService.resendCooldown);
      final second = mailer.lastCode;
      expect(second, isNot(first));

      await expectLater(() => service.verifyTwoFactorEmail(first), failsWith('invalid-verification-code'));
      await service.verifyTwoFactorEmail(second);
      expect(service.twoFactorPending, isFalse);
    });

    test('a new code does not give back the failed attempts', () async {
      await signInPending();
      await service.sendTwoFactorEmail();
      for (var i = 0; i < 2; i++) {
        await expectLater(() => service.verifyTwoFactorEmail(wrongCode()), failsWith('invalid-verification-code'));
      }
      now = now.add(AuthService.resendCooldown);
      await service.sendTwoFactorEmail(resend: true);

      await expectLater(
        () => service.verifyTwoFactorEmail(wrongCode()),
        failsWith('invalid-verification-code', 'Code incorrect. Encore 2 essais.'),
      );
    });

    test('signing out and in again keeps the failed attempts but drops the code', () async {
      final uid = await signInPending();
      await service.sendTwoFactorEmail();
      final code = mailer.lastCode;
      for (var i = 0; i < 4; i++) {
        await expectLater(() => service.verifyTwoFactorEmail(wrongCode()), failsWith('invalid-verification-code'));
      }

      await service.signOut();
      expect(stored(uid)!['hash'], isNull);
      expect(stored(uid)!['failures'], 4);

      await service.signInWithEmail('amel@esprit.tn', 'secret123');
      await expectLater(() => service.verifyTwoFactorEmail(code), failsWith('otp-not-sent'));
      await service.sendTwoFactorEmail();
      await expectLater(() => service.verifyTwoFactorEmail(wrongCode()), failsWith('otp-locked'));
    });

    test('signing out without failed attempts leaves nothing behind', () async {
      final uid = await signInPending();
      await service.sendTwoFactorEmail();
      await service.signOut();
      expect(store.getValue(AuthService.twoFactorEmailKey(uid)), isNull);
    });
  });

  group('échec d\'envoi', () {
    test('a clear French error, no valid code left, and an immediate retry works', () async {
      final uid = await signInPending();
      mailer.failing = true;

      await expectLater(
        () => service.sendTwoFactorEmail(),
        failsWith('email-send-failed',
            "Le code n'a pas pu être envoyé par email. Vérifiez la connexion internet puis réessayez."),
      );
      expect(stored(uid)!['hash'], isNull);
      await expectLater(() => service.verifyTwoFactorEmail('123456'), failsWith('otp-not-sent'));

      mailer.failing = false;
      await service.sendTwoFactorEmail(resend: true);
      await service.verifyTwoFactorEmail(mailer.lastCode);
      expect(service.twoFactorPending, isFalse);
    });

    test('the failure does not carry the original error', () async {
      await signInPending();
      mailer.failing = true;
      try {
        await service.sendTwoFactorEmail();
        fail('should throw');
      } on AuthFailure catch (e) {
        expect(e.cause, isNull);
        expect(e.toString(), isNot(contains('Network')));
      }
    });
  });

  group('SMTP non configuré', () {
    test('the code stays shown in the app, as before', () async {
      mailer.configured = false;
      await signInPending();

      expect(service.twoFactorByEmail, isFalse);
      await expectLater(() => service.sendTwoFactorEmail(), failsWith('otp-not-sent'));

      await service.sendPhoneOtp('+21620123456');
      await service.verifyPhoneOtp(service.demoSmsCode!);
      expect(service.twoFactorPending, isFalse);
      expect(mailer.sent, isEmpty);
    });

    test('the real sender is off when SMTP_USER / SMTP_APP_PASSWORD are empty', () {
      expect(SmtpTwoFactorMailer().isConfigured, isFalse);
      expect(SmtpTwoFactorMailer(config: const AppConfig(smtpUser: '', smtpAppPassword: '')).isConfigured, isFalse);
    });

    test('demo accounts keep the simulated code even with SMTP', () async {
      final demo = await service.registerWithEmail(email: 'demo@esprit.tn', password: 'secret123', fullName: 'Demo');
      final data = {...store.get(AuthService.accountsCollection, demo.id)!};
      final profile = {...store.get(AppConstants.usersCollection, demo.id)!};
      await service.signOut();
      await store.delete(AuthService.accountsCollection, demo.id);
      await store.delete(AppConstants.usersCollection, demo.id);
      await store.set(AuthService.accountsCollection, 'demo-test', data);
      await store.set(AppConstants.usersCollection, 'demo-test', {
        ...profile,
        'twoFactorEnabled': true,
        'isPhoneVerified': true,
        'phoneNumber': '+21620123456',
      });

      await service.signInWithEmail('demo@esprit.tn', 'secret123');
      expect(service.twoFactorPending, isTrue);
      expect(service.twoFactorByEmail, isFalse);
    });
  });

  group('SmtpTwoFactorMailer', () {
    late FakeSmtp smtp;
    setUp(() async => smtp = await FakeSmtp.start());
    tearDown(() => smtp.stop());

    test('sends through the SMTP server', () async {
      final sender = SmtpTwoFactorMailer(server: smtp.config, from: 'campusconnect@example.test');
      expect(sender.isConfigured, isTrue);

      await sender.send(to: 'amel@esprit.tn', subject: TwoFactorEmail.subject, body: 'Bonjour');

      expect(smtp.recipients.single, contains('amel@esprit.tn'));
      expect(smtp.messages.single, contains('subject: ${TwoFactorEmail.subject}'));
      expect(smtp.messages.single, contains('from: CampusConnect <campusconnect@example.test>'));
    });

    test('a refused message throws', () async {
      smtp.failing = true;
      final sender = SmtpTwoFactorMailer(server: smtp.config, from: 'campusconnect@example.test');
      await expectLater(
        () => sender.send(to: 'amel@esprit.tn', subject: TwoFactorEmail.subject, body: 'Bonjour'),
        throwsA(anything),
      );
    });
  });
}
