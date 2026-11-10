import 'dart:convert';
import 'dart:math';

import 'package:campusconnect/core/constants/app_constants.dart';
import 'package:campusconnect/core/utils/auth_failure.dart';
import 'package:campusconnect/core/utils/password_hasher.dart';
import 'package:campusconnect/services/auth_service.dart';
import 'package:campusconnect/services/local_store.dart';
import 'package:campusconnect/services/two_factor_mailer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/fake_two_factor_mailer.dart';
import '../helpers/local_db.dart';
import '../helpers/mocks.dart';

Matcher failsWith(String code, [Object? message]) => throwsA(isA<AuthFailure>()
    .having((f) => f.code, 'code', code)
    .having((f) => f.message, 'message', message ?? anything));

/// Mot de passe oublié par email : code à 6 chiffres, empreinte seulement,
/// 10 minutes, 5 essais, 30 s entre deux codes, même réponse pour une
/// adresse sans compte.
void main() {
  late LocalStore store;
  late FakeMailer mailer;
  late DateTime now;
  late AuthService service;
  late String uid;

  setUp(() async {
    await openTestDatabase();
    store = LocalStore();
    mailer = FakeMailer();
    now = DateTime(2026, 3, 1, 10);
    final storage = MockStorageService();
    when(() => storage.delete(any())).thenAnswer((_) async {});
    service = AuthService(
      store: store,
      storage: storage,
      hasher: PasswordHasher(iterations: 1),
      random: Random(11),
      clock: () => now,
      mailer: mailer,
    );
    final user = await service.registerWithEmail(email: 'amel@esprit.tn', password: 'secret123', fullName: 'Amel Test');
    uid = user.id;
    await service.signOut();
  });

  tearDown(closeTestDatabase);

  Map<String, dynamic>? stored() {
    final raw = store.getValue(AuthService.passwordResetKey(uid));
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  String wrongCode() => mailer.lastCode == '000000' ? '111111' : '000000';

  Future<void> reset(String code, {String email = 'amel@esprit.tn', String password = 'nouveau456'}) =>
      service.resetPasswordWithEmailCode(email: email, code: code, newPassword: password);

  group('demande du code', () {
    test('compte existant : un code à 6 chiffres part à son adresse ; seule une empreinte salée est gardée', () async {
      expect(service.passwordResetByEmail, isTrue);
      final request = await service.requestPasswordReset('  Amel@Esprit.TN ');

      expect(request.byAdmin, isFalse);
      expect(request.email, 'amel@esprit.tn');
      expect(request.expiresAt, now.add(const Duration(minutes: 10)));
      expect(request.resendIn, const Duration(seconds: 30));
      expect(mailer.sent, hasLength(1));
      final mail = mailer.sent.single;
      expect(mail.to, 'amel@esprit.tn');
      expect(mail.subject, PasswordResetEmail.subject);
      final code = mailer.lastCode;
      expect(mail.subject, isNot(contains(code)));
      expect(mail.body, contains('Bonjour Amel Test,'));
      expect(mail.body, contains('valable 10 minutes (jusqu\'à 10h10)'));

      final record = stored()!;
      expect(record['salt'], isNotEmpty);
      expect(record['hash'], isNotEmpty);
      expect(jsonEncode(record), isNot(contains(code)));
      expect(record['hash'], isNot(code));
      // Aucun autre réglage ne contient le code.
      for (final key in [AuthService.sessionKey, AuthService.twoFactorEmailKey(uid)]) {
        expect(store.getValue(key) ?? '', isNot(contains(code)));
      }
    });

    test('adresse sans compte : même réponse, aucun email, rien d’écrit', () async {
      final known = await service.requestPasswordReset('amel@esprit.tn');
      final unknown = await service.requestPasswordReset('personne@esprit.tn');

      expect(mailer.sent, hasLength(1)); // seulement pour le vrai compte
      expect((unknown.byAdmin, unknown.resendIn, unknown.expiresAt), (known.byAdmin, known.resendIn, known.expiresAt));
      expect(unknown.email, 'personne@esprit.tn');
      expect(store.getValue('auth.password_reset.personne@esprit.tn'), isNull);

      // Mêmes réponses ensuite : attente, code faux, essais.
      expect(() => service.requestPasswordReset('personne@esprit.tn', resend: true), failsWith('otp-cooldown'));
      await expectLater(reset('123456', email: 'personne@esprit.tn'),
          failsWith('invalid-verification-code', 'Code incorrect. Encore 4 essais.'));
    });

    test('adresse invalide : refusée', () async {
      expect(() => service.requestPasswordReset('amel'), failsWith('invalid-email'));
      expect(mailer.sent, isEmpty);
    });

    test('un code encore valide n’est pas renvoyé sans « renvoyer »', () async {
      await service.requestPasswordReset('amel@esprit.tn');
      now = now.add(const Duration(minutes: 1));
      final again = await service.requestPasswordReset('amel@esprit.tn');
      expect(mailer.sent, hasLength(1));
      expect(again.resendIn, Duration.zero);
    });
  });

  group('renvoi', () {
    test('30 s entre deux codes ; le nouveau code remplace l’ancien', () async {
      await service.requestPasswordReset('amel@esprit.tn');
      final first = mailer.lastCode;

      now = now.add(const Duration(seconds: 10));
      expect(() => service.requestPasswordReset('amel@esprit.tn', resend: true),
          failsWith('otp-cooldown', 'Patiente 20 s avant de demander un nouveau code.'));

      now = now.add(const Duration(seconds: 20));
      await service.requestPasswordReset('amel@esprit.tn', resend: true);
      final second = mailer.lastCode;
      expect(mailer.sent, hasLength(2));

      if (first != second) {
        await expectLater(reset(first), failsWith('invalid-verification-code'));
      }
      await reset(second);
      await service.signInWithEmail('amel@esprit.tn', 'nouveau456');
    });
  });

  group('vérification', () {
    test('succès : le mot de passe change, l’ancien ne marche plus, le code ne resert pas', () async {
      await service.requestPasswordReset('amel@esprit.tn');
      final code = mailer.lastCode;

      await reset(code);

      expect(stored(), isNull);
      await expectLater(service.signInWithEmail('amel@esprit.tn', 'secret123'), failsWith('invalid-credential'));
      final account = await service.signInWithEmail('amel@esprit.tn', 'nouveau456');
      expect(account.uid, uid);
      await service.signOut();
      await expectLater(reset(code, password: 'encore789'), failsWith('otp-not-sent'));
    });

    test('mot de passe trop faible : refusé sans coûter d’essai', () async {
      await service.requestPasswordReset('amel@esprit.tn');
      for (final weak in ['court1', 'sanschiffre', '12345678']) {
        await expectLater(reset(mailer.lastCode, password: weak), failsWith('weak-password'));
      }
      expect(stored()!['failures'], 0);
      await reset(mailer.lastCode);
    });

    test('code expiré après 10 minutes', () async {
      await service.requestPasswordReset('amel@esprit.tn');
      now = now.add(const Duration(minutes: 9, seconds: 59));
      final code = mailer.lastCode;
      await expectLater(reset(wrongCode()), failsWith('invalid-verification-code'));

      now = now.add(const Duration(seconds: 1));
      await expectLater(reset(code), failsWith('session-expired', 'Le code a expiré. Demandez-en un nouveau.'));
      expect(stored()!['hash'], isNull);
      await service.signInWithEmail('amel@esprit.tn', 'secret123'); // inchangé
    });

    test('5 codes faux : blocage de 5 minutes, même le bon code est refusé', () async {
      await service.requestPasswordReset('amel@esprit.tn');
      final code = mailer.lastCode;
      final messages = <String>[];
      for (var i = 0; i < 4; i++) {
        try {
          await reset(wrongCode());
        } on AuthFailure catch (e) {
          messages.add(e.message);
        }
      }
      expect(messages, [
        'Code incorrect. Encore 4 essais.',
        'Code incorrect. Encore 3 essais.',
        'Code incorrect. Encore 2 essais.',
        'Code incorrect. Dernier essai avant un blocage de 5 minutes.',
      ]);
      await expectLater(reset(wrongCode()), failsWith('otp-locked', "Trop d'essais. Nouvel essai possible dans 5 min."));
      await expectLater(reset(code), failsWith('otp-locked'));
      expect(() => service.requestPasswordReset('amel@esprit.tn', resend: true), failsWith('otp-locked'));
      expect(stored()!['hash'], isNull);

      now = now.add(const Duration(minutes: 5));
      await service.requestPasswordReset('amel@esprit.tn', resend: true);
      await reset(mailer.lastCode);
      await service.signInWithEmail('amel@esprit.tn', 'nouveau456');
    });

    test('adresse sans compte : mêmes messages et même blocage', () async {
      await service.requestPasswordReset('personne@esprit.tn');
      for (var i = 0; i < 4; i++) {
        await expectLater(reset('123456', email: 'personne@esprit.tn'), failsWith('invalid-verification-code'));
      }
      await expectLater(reset('123456', email: 'personne@esprit.tn'), failsWith('otp-locked'));
    });

    test('sans demande : « aucun code envoyé »', () async {
      await expectLater(reset('123456'), failsWith('otp-not-sent'));
      await expectLater(reset('123456', email: 'personne@esprit.tn'), failsWith('otp-not-sent'));
    });

    test('un code de double authentification ne sert pas à réinitialiser', () async {
      await store.update(AppConstants.usersCollection, uid, {
        'twoFactorEnabled': true,
        'isPhoneVerified': true,
        'phoneNumber': '+21620123456',
      });
      await service.signInWithEmail('amel@esprit.tn', 'secret123');
      await service.sendTwoFactorEmail();
      final twoFactorCode = mailer.lastCode;
      // Même enregistrement (sel, empreinte) recopié côté réinitialisation.
      await store.setValue(AuthService.passwordResetKey(uid), store.getValue(AuthService.twoFactorEmailKey(uid)));
      await service.signOut();
      await expectLater(reset(twoFactorCode), failsWith('invalid-verification-code'));
    });
  });

  group('échec d’envoi', () {
    test('pas de réseau : erreur en français, aucun code valide laissé, nouvel essai possible tout de suite', () async {
      mailer.failing = true;
      await expectLater(
        service.requestPasswordReset('amel@esprit.tn'),
        failsWith('email-send-failed',
            "Le code n'a pas pu être envoyé par email. Vérifiez la connexion internet puis réessayez."),
      );
      final record = stored()!;
      expect(record['hash'], isNull);
      expect(record['salt'], isNull);
      await expectLater(reset('123456'), failsWith('otp-not-sent'));

      mailer.failing = false;
      await service.requestPasswordReset('amel@esprit.tn', resend: true);
      expect(mailer.sent, hasLength(1));
      await reset(mailer.lastCode);
    });

    test('le message d’erreur ne cite ni l’exception ni la configuration', () async {
      mailer.failing = true;
      try {
        await service.requestPasswordReset('amel@esprit.tn');
        fail('doit échouer');
      } on AuthFailure catch (e) {
        expect(e.message, isNot(contains('Socket')));
        expect(e.message, isNot(contains('unreachable')));
      }
    });
  });

  group('sans email : réinitialisation par un administrateur', () {
    test('SMTP non configuré : réponse « admin », aucun email, l’admin peut toujours réinitialiser', () async {
      mailer.configured = false;
      expect(service.passwordResetByEmail, isFalse);
      final request = await service.requestPasswordReset('amel@esprit.tn');
      expect(request.byAdmin, isTrue);
      expect(mailer.sent, isEmpty);
      expect(stored(), isNull);

      final temporary = await service.resetPasswordByAdmin(uid);
      await service.signInWithEmail('amel@esprit.tn', temporary);
    });

    test('compte de démonstration : réponse « admin », aucun email, aucun code accepté', () async {
      await store.set(AuthService.accountsCollection, 'demo-amel', {
        'email': 'amel.demo@esprit.tn',
        'password': PasswordHasher(iterations: 1).hash('demo1234').toMap(),
      });
      final request = await service.requestPasswordReset('amel.demo@esprit.tn');
      expect(request.byAdmin, isTrue);
      expect(mailer.sent, isEmpty);
      expect(store.getValue(AuthService.passwordResetKey('demo-amel')), isNull);
      await expectLater(reset('123456', email: 'amel.demo@esprit.tn'), failsWith('otp-not-sent'));
      await service.signInWithEmail('amel.demo@esprit.tn', 'demo1234');
    });
  });

  test('suppression du compte : le code de réinitialisation disparaît', () async {
    await service.requestPasswordReset('amel@esprit.tn');
    expect(stored(), isNotNull);
    await service.signInWithEmail('amel@esprit.tn', 'secret123');
    await service.deleteAccount(password: 'secret123');
    expect(stored(), isNull);
  });
}
