import 'dart:async';
import 'dart:io';

import 'package:campusconnect/core/config/app_config.dart';
import 'package:campusconnect/core/constants/app_constants.dart';
import 'package:campusconnect/core/theme/app_theme.dart';
import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/services/stages/cv_storage.dart';
import 'package:campusconnect/services/stages/stage_services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mailer/smtp_server.dart';

import 'local_db.dart';

/// google_fonts tente un téléchargement impossible en test : on l'ignore.
Future<void> silenceFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await runZonedGuarded(() async {
    AppTheme.light;
    AppTheme.dark;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }, (_, __) {});
}

/// [StageServices] complets sur la base partagée en mémoire.
Future<StageServices> makeStage({
  AppConfig config = const AppConfig(smtpUser: '', smtpAppPassword: '', geminiApiKey: ''),
  SmtpServer? smtpServer,
  http.Client? httpClient,
}) async {
  await openTestDatabase();
  final dir = await Directory.systemTemp.createTemp('campus_test');
  return StageServices(
    config: config,
    cvStorage: CvStorage(directory: () async => dir),
    smtpServer: smtpServer,
    emailFrom: 'campus@test.local',
    httpClient: httpClient,
  );
}

Future<void> closeStage(StageServices s) async {
  s.dispose();
  await closeTestDatabase();
}

int _next = 0;

/// Crée un compte directement dans la collection `users` de l'app.
Future<AppUser> makeUser(
  StageServices s, {
  required String email,
  required String fullName,
  required UserRole role,
  List<String> skills = const [],
}) async {
  final user = AppUser(
    id: 'user-${_next++}',
    fullName: fullName,
    email: email,
    role: role,
    skills: skills,
    createdAt: DateTime.utc(2026, 1, 1),
  );
  await s.store.set(AppConstants.usersCollection, user.id, user.toMap());
  return user;
}

/// Ajoute une compétence au compte et renvoie sa version à jour.
Future<AppUser> addSkill(StageServices s, AppUser user, String skill) async {
  final updated = user.copyWith(skills: [...user.skills, skill]);
  await s.store.set(AppConstants.usersCollection, user.id, updated.toMap());
  return updated;
}

Future<PickedCv> makeCv({String name = 'cv.pdf', int bytes = 128}) async {
  final dir = await Directory.systemTemp.createTemp('campus_cv');
  final file = File('${dir.path}/$name')..writeAsBytesSync(List.filled(bytes, 65));
  return PickedCv(path: file.path, name: name);
}
