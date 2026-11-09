import 'dart:convert';

import 'package:campusconnect/core/config/app_config.dart';
import 'package:campusconnect/models/job_offer_model.dart';
import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/services/stages/matching_service.dart';
import 'package:campusconnect/services/stages/stage_services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/stage_env.dart';

void main() {

  JobOfferModel job(List<String> skills, {String description = 'desc'}) =>
      JobOfferModel(id: 'j', recruiterId: 'r', title: 'T', companyName: 'C', type: JobType.emploi, location: 'L', description: description, requiredSkills: skills, postedAt: DateTime(2026));

  group('local score', () {
    test('share of the requested skills, case-insensitive', () {
      final m = MatchingService.localScore(['flutter', 'SQL'], job(['Flutter', 'Docker', 'Git', 'SQL']));
      expect(m.score, 50);
      expect(m.isAi, isFalse);
      expect(m.reason, contains('Flutter'));
    });

    test('no student skill gives 0 and invites to complete the profile', () {
      final m = MatchingService.localScore([], job(['Flutter']));
      expect(m.score, 0);
      expect(m.reason, contains('compétences'));
    });

    test('offer without skills falls back on its description, capped at 100', () {
      final skills = ['a1', 'b2', 'c3', 'd4', 'e5', 'f6'];
      expect(MatchingService.localScore(skills, job([], description: skills.join(' '))).score, 100);
      expect(MatchingService.localScore(['flutter'], job([], description: 'Python')).score, 0);
    });
  });

  group('Gemini', () {
    late StageServices s;
    late AppUser student;
    late JobOfferModel offer;
    late int calls;
    late http.Response Function(http.Request) reply;
    http.Request? last;

    setUp(() async {
      calls = 0;
      last = null;
      reply = (_) => http.Response('{}', 500);
      s = await makeStage(
        config: const AppConfig(smtpUser: '', smtpAppPassword: '', geminiApiKey: 'KEY', geminiModel: 'gemini-test'),
        httpClient: MockClient((r) async {
          calls++;
          last = r;
          return reply(r);
        }),
      );
      student = await makeUser(s, email: 's@x.test', fullName: 'Sara', role: UserRole.student);
      student = await addSkill(s, student, 'Flutter');
      final r = await makeUser(s, email: 'r@x.test', fullName: 'Rec', role: UserRole.recruiter);
      offer = await s.jobs.save(recruiterId: r.id, title: 'Dev', company: 'C', type: JobType.emploi, location: 'L', description: 'D', skills: ['Flutter', 'Go']);
    });
    tearDown(() => closeStage(s));

    http.Response ok(int score) => http.Response.bytes(
          utf8.encode(jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'text': jsonEncode([
                        {'id': offer.id, 'score': score, 'raison': 'Très bon profil'}
                      ])
                    }
                  ]
                }
              }
            ]
          })),
          200,
        );

    test('stores the score, sends the key in a header, not in the URL', () async {
      reply = (_) => ok(96);
      await s.matching.refresh(student, [offer]);
      final m = (await s.matching.scores(student, [offer]))[offer.id]!;
      expect((m.score, m.isAi, m.reason), (96, true, 'Très bon profil'));
      expect(last!.headers['x-goog-api-key'], 'KEY');
      expect(last!.url.toString(), isNot(contains('KEY')));
      expect(last!.url.path, contains('gemini-test'));
    });

    test('does not call again while nothing changed; a profile change refreshes', () async {
      reply = (_) => ok(80);
      await s.matching.refresh(student, [offer]);
      await s.matching.refresh(student, [offer]);
      expect(calls, 1);

      student = await addSkill(s, student, 'Go');
      expect((await s.matching.scores(student, [offer]))[offer.id]!.isAi, isFalse);
      await s.matching.refresh(student, [offer]);
      expect(calls, 2);
    });

    test('clamps out-of-range scores', () async {
      reply = (_) => ok(250);
      await s.matching.refresh(student, [offer]);
      expect((await s.matching.scores(student, [offer]))[offer.id]!.score, 100);
    });

    for (final (name, body, code) in [
      ('HTTP error', '{"error":1}', 429),
      ('malformed shape', '{"candidates":[]}', 200),
      ('text is not JSON', '{"candidates":[{"content":{"parts":[{"text":"oops"}]}}]}', 200),
    ]) {
      test('$name keeps the local estimate and backs off', () async {
        reply = (_) => http.Response(body, code);
        await s.matching.refresh(student, [offer]);
        await s.matching.refresh(student, [offer]);
        expect(calls, code == 200 || const {400, 401, 403}.contains(code) ? 1 : 2);
        final m = (await s.matching.scores(student, [offer]))[offer.id]!;
        expect((m.isAi, m.score), (false, 50));
      });
    }

    test('falls back to the backup model when the main one is overloaded', () async {
      reply = (r) => r.url.path.contains(MatchingService.backupModel) ? ok(90) : http.Response('{}', 503);
      await s.matching.refresh(student, [offer]);
      expect(calls, 2);
      final m = (await s.matching.scores(student, [offer]))[offer.id]!;
      expect((m.isAi, m.score), (true, 90));
    });

    test('a refused key does not try the backup model', () async {
      reply = (_) => http.Response('{}', 403);
      await s.matching.refresh(student, [offer]);
      expect(calls, 1);
    });

    test('without a key, no network call', () async {
      var called = false;
      final local = await makeStage(httpClient: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }));
      final u = await makeUser(local, email: 'z@x.test', fullName: 'Zed', role: UserRole.student);
      await local.matching.refresh(u, [offer]);
      expect(called, isFalse);
      await closeStage(local);
    });
  });
}
