import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/screens/stages_emploi/recruiter/job_form_screen.dart';
import 'package:campusconnect/services/stages/stage_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../helpers/authenticated.dart';
import '../helpers/stage_env.dart';

void main() {
  late AuthHarness h;
  setUp(() => h = AuthHarness());
  tearDown(() => h.dispose());

  testWidgets('several skills can be added one after the other', (t) async {
    final s = (await t.runAsync(makeStage))!;
    addTearDown(() => closeStage(s));
    await h.signIn(t, user: AppUser(id: 'rec', fullName: 'Rec', email: 'r@x.test', role: UserRole.recruiter, createdAt: DateTime(2026)));
    t.view.physicalSize = const Size(420, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await h.pump(t, Provider<StageServices>.value(value: s, child: const JobFormScreen()), push: false);

    final field = find.descendant(of: find.byKey(const ValueKey('job-skill-input')), matching: find.byType(TextFormField));
    for (final skill in ['Flutter', 'Kotlin', 'SQL']) {
      await t.enterText(field, skill);
      await t.pump();
      await t.ensureVisible(find.byKey(const ValueKey('job-skill-add')));
      await t.tap(find.byKey(const ValueKey('job-skill-add')));
      await t.pump();
      expect(find.widgetWithText(InputChip, skill), findsOneWidget);
      expect(t.widget<TextFormField>(field).controller!.text, isEmpty);
    }
  });
}
