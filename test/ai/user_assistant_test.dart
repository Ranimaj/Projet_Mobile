import 'dart:convert';

import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/services/ai/user_assistant.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/authenticated.dart';

http.Response _answer(String text) => http.Response.bytes(
      utf8.encode(jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': text},
              ],
            },
          },
        ],
      })),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  const local = LocalUserAssistant();
  Future<AssistantMessage> ask(String q, [AppUser? user]) =>
      local.reply(AssistantRequest(question: q, user: user ?? sampleUser));

  group('ProfileHealth', () {
    test('lists what is missing and computes the percentage', () {
      final h = ProfileHealth.of(sampleUser); // filière, année, 1 compétence
      expect(h.missing.map((s) => s.label),
          ['Photo de profil', 'Carte étudiant vérifiée', 'Téléphone vérifié', 'Double authentification']);
      expect(h.percent, 33);
    });

    test('a complete profile is 100 %', () {
      final full = sampleUser.copyWith(
        photoUrl: 'https://x/p.jpg',
        isVerifiedStudent: true,
        isPhoneVerified: true,
        twoFactorEnabled: true,
      );
      expect(ProfileHealth.of(full).missing, isEmpty);
      expect(ProfileHealth.of(full).percent, 100);
    });
  });

  group('LocalUserAssistant', () {
    test('profile question lists missing steps with their screens', () async {
      final r = await ask('Comment compléter mon profil ?');
      expect(r.text, contains('33 %'));
      expect(r.actions, [AssistantAction.editProfile, AssistantAction.studentCard, AssistantAction.verifyPhone]);
    });

    test('student card answer follows the real card status', () async {
      final none = await ask('Où en est ma carte étudiant ?');
      expect(none.text, contains('pas encore envoyé'));

      final rejected = await ask(
        'ma carte ?',
        sampleUser.copyWith(
            studentCard: const StudentCard(status: StudentCardStatus.rejected, rejectReason: 'Photo floue')),
      );
      expect(rejected.text, contains('Photo floue'));
      expect(rejected.actions, [AssistantAction.studentCard]);

      final ok = await ask('badge vérifié ?', sampleUser.copyWith(isVerifiedStudent: true));
      expect(ok.text, contains('vérifiée'));
      expect(ok.actions, isEmpty);
    });

    test('a greeting followed by a question answers the question', () async {
      final r = await ask('Salut, comment changer mon mot de passe ?');
      expect(r.actions, [AssistantAction.changePassword]);
    });

    test('short keywords only match whole word starts', () async {
      // « hi » ne doit pas être trouvé dans « chiffre ».
      final r = await ask('chiffre');
      expect(r.text, contains('pas bien compris'));
    });

    test('understands darija greetings', () async {
      final r = await ask('aslema');
      expect(r.text, startsWith('Salut Amel'));
    });

    test('never asks for a password', () async {
      final r = await ask('mot de passe oublié');
      expect(r.text, contains('Je ne te demanderai jamais'));
    });
  });

  group('GeminiUserAssistant', () {
    test('sends account state and history, uses the answer, keeps local actions', () async {
      late Map<String, dynamic> body;
      final g = GeminiUserAssistant(
        apiKey: 'cle-test',
        model: 'gemini-test',
        backupModels: const [],
        client: MockClient((r) async {
          body = jsonDecode(r.body) as Map<String, dynamic>;
          return _answer('  Va dans Profil › Carte étudiant.  ');
        }),
      );
      final r = await g.reply(AssistantRequest(
        question: 'ma carte étudiant ?',
        user: sampleUser,
        history: const [AssistantMessage.user('Salut'), AssistantMessage.bot('Salut Amel !')],
      ));
      expect(r.text, 'Va dans Profil › Carte étudiant.');
      expect(r.actions, [AssistantAction.studentCard]);

      final system = body['systemInstruction']['parts'][0]['text'] as String;
      expect(system, contains('Génie Logiciel'));
      expect(system, contains('Carte étudiant : pas encore envoyée'));
      final contents = body['contents'] as List;
      expect([for (final c in contents) c['role']], ['user', 'model', 'user']);
    });

    test('falls back to the local assistant on error or without a key', () async {
      final failing = GeminiUserAssistant(
        apiKey: 'cle-test',
        backupModels: const [],
        client: MockClient((_) async => http.Response('busy', 503)),
      );
      final r = await failing.reply(AssistantRequest(question: 'mon téléphone', user: sampleUser));
      expect(r.actions, [AssistantAction.verifyPhone]);

      final noKey = GeminiUserAssistant(
        apiKey: '',
        client: MockClient((_) async => fail('no call without a key')),
      );
      expect((await noKey.reply(AssistantRequest(question: 'thème', user: sampleUser))).text, contains('Thème'));
    });
  });
}
