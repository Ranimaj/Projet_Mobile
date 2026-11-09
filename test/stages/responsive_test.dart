import 'package:campusconnect/core/theme/app_theme.dart';
import 'package:campusconnect/models/job_offer_model.dart';
import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/screens/stages_emploi/admin/admin_dashboard_screen.dart';
import 'package:campusconnect/screens/stages_emploi/admin/admin_emails_screen.dart';
import 'package:campusconnect/screens/stages_emploi/admin/admin_jobs_screen.dart';
import 'package:campusconnect/screens/stages_emploi/recruiter/application_review_screen.dart';
import 'package:campusconnect/screens/stages_emploi/recruiter/job_form_screen.dart';
import 'package:campusconnect/screens/stages_emploi/recruiter/job_manage_screen.dart';
import 'package:campusconnect/screens/stages_emploi/stages_list_screen.dart';
import 'package:campusconnect/screens/stages_emploi/student/application_detail_screen.dart';
import 'package:campusconnect/screens/stages_emploi/student/apply_flow_screen.dart';
import 'package:campusconnect/screens/stages_emploi/student/job_detail_screen.dart';
import 'package:campusconnect/services/stages/stage_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import '../helpers/authenticated.dart';
import '../helpers/stage_env.dart';

/// Tous les écrans du module sur petits téléphones et grand texte : un
/// débordement de mise en page fait échouer le test.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('fr_FR');
    await silenceFonts();
  });
  late AuthHarness h;
  setUp(() => h = AuthHarness());
  tearDown(() => h.dispose());

  const sizes = {
    'small 320x568': Size(320, 568),
    'android 360x740': Size(360, 740),
    'iphone 390x844': Size(390, 844),
    'tablet 820x1180': Size(820, 1180),
  };

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 6; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await t.pump(const Duration(milliseconds: 80));
    }
  }

  for (final MapEntry(key: label, value: size) in sizes.entries) {
    for (final scale in [1.0, 1.5]) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        testWidgets('stage screens fit: $label, text x$scale, $mode', (t) async {
          late StageServices s;
          late AppUser student;
          late AppUser recruiter;
          late AppUser admin;
          late String jobId;
          late String appId;
          await t.runAsync(() async {
            s = await makeStage();
            student = await makeUser(s, email: 'etu@x.test', fullName: 'Sara Ben Ali', role: UserRole.student, skills: const ['Flutter', 'SQL']);
            recruiter = await makeUser(s, email: 'r@x.test', fullName: 'Rec', role: UserRole.recruiter);
            admin = await makeUser(s, email: 'a@x.test', fullName: 'Admin', role: UserRole.admin);
            final job = await s.jobs.save(
              recruiterId: recruiter.id,
              title: 'Stage PFE Développeur Mobile Flutter avec un intitulé assez long',
              company: 'Une entreprise au nom particulièrement long',
              type: JobType.stage,
              location: 'Tunis, Lac 2',
              duration: '6 mois',
              description: 'Description de la mission. ' * 12,
              requirements: 'Prérequis détaillés. ' * 6,
              skills: const ['Flutter', 'Kotlin', 'SQL', 'Git', 'Docker', 'Intégration continue'],
              deadline: DateTime.now().add(const Duration(days: 20)),
            );
            jobId = job.id;
            final app = await s.applications.apply(
              jobId: job.id,
              student: student,
              cv: await makeCv(name: 'curriculum_vitae_avec_un_nom_de_fichier_tres_long.pdf'),
              motivationLetter: 'Lettre de motivation assez longue pour le test. ' * 6,
              message: 'Message au recruteur.',
            );
            appId = app.id;
            await s.applications.moveTo(app.id, ApplicationStatus.hrInterview, recruiterId: recruiter.id, note: 'Mardi 10h');
          });
          addTearDown(() => closeStage(s));
          t.view.physicalSize = size;
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);

          Widget app(Widget home) => MediaQuery(
                data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
                child: MultiProvider(
                  providers: [
                    ChangeNotifierProvider<AuthProvider>.value(value: h.provider),
                    Provider<StageServices>.value(value: s),
                  ],
                  child: MaterialApp(theme: AppTheme.light, darkTheme: AppTheme.dark, themeMode: mode, home: home),
                ),
              );

          Future<void> asRole(AppUser user, List<Widget> screens, {List<String> tabs = const []}) async {
            await h.signIn(t, user: user);
            for (final screen in screens) {
              await t.pumpWidget(app(KeyedSubtree(key: UniqueKey(), child: screen)));
              await settle(t);
              if (screen is StagesListScreen) {
                for (final tab in tabs) {
                  await t.tap(find.byKey(ValueKey('stages-tab-$tab')));
                  await settle(t);
                }
              }
            }
          }

          await asRole(student, [
            const StagesListScreen(),
            JobDetailScreen(jobId: jobId),
            ApplicationDetailScreen(applicationId: appId),
            ApplyFlowScreen(jobId: jobId, jobTitle: 'Un intitulé de poste vraiment très long pour vérifier', company: 'Atlas Software'),
          ], tabs: const ['Candidatures', 'Mon profil', 'Offres']);
          await asRole(recruiter, [
            const StagesListScreen(),
            ApplicationReviewScreen(applicationId: appId),
            JobManageScreen(jobId: jobId),
            const JobFormScreen(),
          ], tabs: const ['Candidats', 'Mes offres']);
          await asRole(admin, const [
            StagesListScreen(),
            AdminDashboardScreen(),
            AdminJobsScreen(),
            AdminEmailsScreen(),
          ]);
          await t.pumpWidget(const SizedBox());
        }, timeout: const Timeout(Duration(minutes: 2)));
      }
    }
  }
}
