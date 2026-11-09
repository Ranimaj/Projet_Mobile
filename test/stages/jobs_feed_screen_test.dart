import 'package:campusconnect/models/job_offer_model.dart';
import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/screens/stages_emploi/student/jobs_feed_screen.dart';
import 'package:campusconnect/services/stages/stage_services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import '../helpers/authenticated.dart';
import '../helpers/stage_env.dart';

void main() {
  late AuthHarness h;
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    await silenceFonts();
  });
  setUp(() => h = AuthHarness());
  tearDown(() => h.dispose());

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 80));
    }
  }

  testWidgets('the score follows the skills of the signed-in student', (t) async {
    final s = (await t.runAsync(makeStage))!;
    addTearDown(() => closeStage(s));
    final student = AppUser(id: 'etu', fullName: 'Sara', email: 'e@x.test', role: UserRole.student, createdAt: DateTime(2026));
    await t.runAsync(() => s.jobs.save(
        recruiterId: 'r',
        title: 'Stage',
        company: 'C',
        type: JobType.stage,
        location: 'L',
        description: 'D',
        skills: const ['Flutter', 'Kotlin']));
    await h.signIn(t, user: student);
    await h.pump(t, Provider<StageServices>.value(value: s, child: const JobsFeedScreen()), push: false);
    await settle(t);
    expect(find.text('0% estimé'), findsOneWidget);

    await h.signIn(t, user: student.copyWith(skills: const ['Flutter']));
    await settle(t);
    expect(find.text('50% estimé'), findsOneWidget);
  });

  testWidgets('two offers with the same title can be listed', (t) async {
    final s = (await t.runAsync(makeStage))!;
    addTearDown(() => closeStage(s));
    final student = AppUser(id: 'etu', fullName: 'Sara', email: 'e@x.test', role: UserRole.student, createdAt: DateTime(2026));
    await t.runAsync(() async {
      for (final company in ['A', 'B']) {
        await s.jobs.save(recruiterId: 'r', title: 'Stage', company: company, type: JobType.stage, location: 'L', description: 'D');
      }
    });
    await h.signIn(t, user: student);
    await h.pump(t, Provider<StageServices>.value(value: s, child: const JobsFeedScreen()), push: false);
    await settle(t);
    expect(find.text('Stage'), findsWidgets);
    expect(t.takeException(), isNull);
  });
}
