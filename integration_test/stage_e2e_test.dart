import 'dart:io';

import 'package:campusconnect/core/utils/local_database.dart';
import 'package:campusconnect/main.dart';
import 'package:campusconnect/models/job_offer_model.dart';
import 'package:campusconnect/models/stage_records.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/services/app_prefs.dart';
import 'package:campusconnect/services/auth_service.dart';
import 'package:campusconnect/services/demo_seed.dart';
import 'package:campusconnect/services/stages/cv_storage.dart';
import 'package:campusconnect/services/stages/stage_services.dart';
import 'package:campusconnect/widgets/floating_nav_bar.dart';
import 'package:campusconnect/widgets/stages/job_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../test/helpers/fake_smtp.dart';

/// Parcours complet sur l'appareil, avec une base SQLite dédiée au test et un
/// serveur SMTP local : aucun vrai email ne part.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const recruiterEmail = 'recruteur@vermeg.tn';
  const studentEmail = 'yassine@campus.test';
  const adminEmail = 'admin@esprit.tn';
  const password = 'Campus2026!';
  const jobTitle = 'Stage Developpeur Mobile';
  const company = 'Nova Tech';

  testWidgets('recruteur, étudiant et admin : parcours complet', (t) async {
    t.testTextInput.register();
    await initializeDateFormatting('fr_FR');
    SharedPreferences.setMockInitialValues({'onboarding_seen': true});
    final prefs = await AppPrefs.load();
    final smtp = await FakeSmtp.start();

    final dbPath = p.join(await getDatabasesPath(), 'e2e_stage.db');
    await deleteDatabase(dbPath);
    await LocalDatabase.open(path: dbPath);
    await DemoSeed().ensureSeeded();

    final accounts = AuthService();
    await accounts.registerWithEmail(email: studentEmail, password: password, fullName: 'Yassine Trabelsi');
    await accounts.signOut();

    final tmp = await getTemporaryDirectory();
    final cvFile = File(p.join(tmp.path, 'cv_yassine.pdf'))..writeAsBytesSync(List.filled(2048, 37));
    final stages = StageServices(
      cvStorage: CvStorage(picker: () async => PickedCv(path: cvFile.path, name: 'cv_yassine.pdf')),
      smtpServer: smtp.config,
      emailFrom: 'campus@test.local',
    );

    await t.pumpWidget(CampusConnectApp(prefs: prefs, stages: stages));

    Future<void> waitFor(Finder finder, {int seconds = 20}) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (finder.evaluate().isEmpty) {
        if (DateTime.now().isAfter(end)) {
          final visible = find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().join(' | ');
          // ignore: avoid_print
          print('E2EDUMP $visible');
          fail('Introuvable après ${seconds}s : $finder');
        }
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.pump(const Duration(milliseconds: 400));
    }

    Future<void> shot(String name) async {
      await t.pump(const Duration(milliseconds: 500));
      // ignore: avoid_print
      print('E2ESHOT $name');
      final end = DateTime.now().add(const Duration(milliseconds: 1800));
      while (DateTime.now().isBefore(end)) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> clearSnacks() async {
      for (final e in find.byType(ScaffoldMessenger).evaluate()) {
        (e as StatefulElement).state as ScaffoldMessengerState
          ..removeCurrentSnackBar()
          ..clearSnackBars();
      }
      await t.pump(const Duration(milliseconds: 300));
    }

    Future<void> tapOn(Finder finder) async {
      await waitFor(finder);
      await t.ensureVisible(finder.first);
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(finder.first);
      await t.pump(const Duration(milliseconds: 400));
    }

    Future<void> fill(String key, String text) async {
      final field = find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(TextFormField));
      await waitFor(field);
      await t.ensureVisible(field);
      await t.pump(const Duration(milliseconds: 200));
      await t.enterText(field, text);
      await t.pump(const Duration(milliseconds: 200));
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pump(const Duration(milliseconds: 500));
    }

    Future<void> back() async {
      await clearSnacks();
      await tapOn(find.byType(BackButton));
      await t.pump(const Duration(milliseconds: 500));
    }

    /// Change de compte sans repasser par les écrans de connexion, testés ailleurs.
    Future<void> signInAs(String email) async {
      final auth = t.element(find.byType(RootRouter)).read<AuthProvider>();
      if (auth.status == AuthStatus.authenticated) await auth.logout();
      await t.pump(const Duration(milliseconds: 300));
      expect(await auth.login(email, password), isTrue, reason: 'connexion $email : ${auth.errorMessage}');
      await waitFor(find.byType(FloatingNavBar));
    }

    Future<void> openStages() async {
      await clearSnacks();
      await tapOn(find.descendant(of: find.byType(FloatingNavBar), matching: find.byIcon(Icons.work_rounded)));
      await t.pump(const Duration(milliseconds: 500));
    }

    Future<void> stagesTab(String label) async {
      await clearSnacks();
      await tapOn(find.byKey(ValueKey('stages-tab-$label')));
      await t.pump(const Duration(milliseconds: 400));
    }

    await waitFor(find.byType(RootRouter));

    // --- Le recruteur publie une offre ---------------------------------------
    await signInAs(recruiterEmail);
    await openStages();
    await shot('01_recruiter_jobs');
    await tapOn(find.byKey(const ValueKey('job-add')));
    await fill('job-title', jobTitle);
    await fill('job-company', company);
    await fill('job-location', 'Tunis');
    await fill('job-description', 'Developpement d une application mobile Flutter avec stockage SQLite.');
    await fill('job-skill-input', 'Flutter');
    await tapOn(find.byKey(const ValueKey('job-skill-add')));
    await fill('job-skill-input', 'Kotlin');
    await tapOn(find.byKey(const ValueKey('job-skill-add')));
    await shot('02_recruiter_job_form');
    await tapOn(find.byKey(const ValueKey('job-save')));
    await waitFor(find.text(jobTitle));
    await shot('03_recruiter_jobs_after');

    // --- L'étudiant complète son profil et postule ---------------------------
    await signInAs(studentEmail);
    await openStages();
    await stagesTab('Mon profil');
    await tapOn(find.byKey(const ValueKey('add-skill')));
    await fill('skill-name', 'Flutter');
    await tapOn(find.byKey(const ValueKey('skill-save')));
    await waitFor(find.byKey(const ValueKey('skill-Flutter')));
    await shot('04_student_profile');

    await stagesTab('Offres');
    final card = find.widgetWithText(JobCard, jobTitle);
    await waitFor(card);
    await waitFor(find.descendant(of: card, matching: find.text('50% estimé')));
    await shot('05_student_feed');
    await tapOn(card);
    await waitFor(find.byKey(const ValueKey('apply-start')));
    await shot('06_student_job_detail');
    await tapOn(find.byKey(const ValueKey('apply-start')));

    await tapOn(find.byKey(const ValueKey('apply-next')));
    await waitFor(find.text('Ajoutez votre CV pour continuer.'));
    await tapOn(find.byKey(const ValueKey('apply-pick-cv')));
    await waitFor(find.text('cv_yassine.pdf'));
    await shot('07_apply_cv');
    await tapOn(find.byKey(const ValueKey('apply-next')));
    await fill('apply-letter', 'Madame, Monsieur, je souhaite rejoindre votre equipe pour mon projet de fin d etudes.');
    await tapOn(find.byKey(const ValueKey('apply-next')));
    await fill('apply-message', 'Je suis disponible des fevrier.');
    await tapOn(find.byKey(const ValueKey('apply-next')));
    await waitFor(find.text('Vérification'));
    await shot('08_apply_review');
    await tapOn(find.byKey(const ValueKey('apply-next')));
    await waitFor(find.text('Voir ma candidature'));
    await back();

    await stagesTab('Candidatures');
    final application = find.widgetWithText(ApplicationCard, jobTitle);
    await waitFor(find.descendant(of: application, matching: find.text('En attente')));
    await shot('09_student_applications');
    expect(smtp.messages, hasLength(1));

    // --- Le recruteur fait avancer la candidature ----------------------------
    await signInAs(recruiterEmail);
    await openStages();
    await stagesTab('Candidats');
    await tapOn(find.widgetWithText(ApplicationCard, 'Yassine Trabelsi'));
    await waitFor(find.byKey(const ValueKey('status-next')));
    await shot('10_recruiter_review');

    var expected = 1;
    for (final step in [ApplicationStatus.hrInterview, ApplicationStatus.technicalInterview, ApplicationStatus.accepted]) {
      await tapOn(find.byKey(const ValueKey('status-next')));
      await fill('status-note', 'Etape ${step.label}, rendez-vous mardi a 10h.');
      await tapOn(find.byKey(const ValueKey('status-confirm')));
      expected++;
      final end = DateTime.now().add(const Duration(seconds: 20));
      while (smtp.messages.length < expected && DateTime.now().isBefore(end)) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(smtp.messages, hasLength(expected), reason: 'email de ${step.label}');
      await waitFor(find.textContaining('email envoyé au candidat'));
      await clearSnacks();
    }
    await waitFor(find.text('Acceptée'));
    expect(find.byKey(const ValueKey('status-next')), findsNothing);
    await shot('11_recruiter_accepted');
    await back();

    // --- L'étudiant voit le résultat -----------------------------------------
    await signInAs(studentEmail);
    await openStages();
    await stagesTab('Candidatures');
    await waitFor(find.descendant(of: application, matching: find.text('Acceptée')));
    await tapOn(application);
    await waitFor(find.text('Suivi'));
    await shot('12_student_timeline');
    await back();

    // --- L'admin surveille ---------------------------------------------------
    await signInAs(adminEmail);
    await openStages();
    await waitFor(find.text(jobTitle));
    await shot('13_admin_jobs');

    final stored = await stages.emails.all();
    expect(stored.where((e) => e.recipient == studentEmail), hasLength(4));
    expect(stored.every((e) => e.status == EmailStatus.sent), isTrue);
    final accepted = (await stages.applications.byStudent(
            (await stages.applications.all()).firstWhere((a) => a.studentEmail == studentEmail).candidateId))
        .single;
    expect(accepted.status, ApplicationStatus.accepted);
    expect(accepted.history, hasLength(4));
    expect(File(accepted.cvUrl!).existsSync(), isTrue);

    await smtp.stop();
  }, timeout: const Timeout(Duration(minutes: 8)));
}
