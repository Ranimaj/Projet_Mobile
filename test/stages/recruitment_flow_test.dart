import 'dart:io';

import 'package:campusconnect/models/job_offer_model.dart';
import 'package:campusconnect/models/stage_records.dart';
import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/services/stages/application_repository.dart';
import 'package:campusconnect/services/stages/cv_storage.dart';
import 'package:campusconnect/services/stages/stage_services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_smtp.dart';
import '../helpers/stage_env.dart';

void main() {
  late FakeSmtp smtp;
  late StageServices s;
  late AppUser recruiter;
  late AppUser student;
  late JobOfferModel job;

  const letter = 'Madame, Monsieur, je souhaite vivement rejoindre votre équipe mobile cette année.';
  const message = 'Disponible dès février.';

  setUp(() async {
    smtp = await FakeSmtp.start();
    s = await makeStage(smtpServer: smtp.config);
    recruiter = await makeUser(s, email: 'r@x.test', fullName: 'Rec', role: UserRole.recruiter);
    student = await makeUser(s, email: 'etu@x.test', fullName: 'Sara <b>B</b>', role: UserRole.student);
    job = await s.jobs.save(recruiterId: recruiter.id, title: 'Stage Flutter', company: 'Acme', type: JobType.stage, location: 'Tunis', description: 'D');
  });

  tearDown(() async {
    await closeStage(s);
    await smtp.stop();
  });

  Future<ApplicationModel> apply() async =>
      s.applications.apply(jobId: job.id, student: student, cv: await makeCv(), motivationLetter: letter, message: message);

  test('full success path: every step updates status, history and sends one email', () async {
    final a = await apply();
    expect(a.status, ApplicationStatus.pending);
    expect(File(a.cvUrl!).existsSync(), isTrue);
    expect(smtp.messages, hasLength(1));

    for (final step in [ApplicationStatus.hrInterview, ApplicationStatus.technicalInterview, ApplicationStatus.accepted]) {
      expect(await s.applications.moveTo(a.id, step, recruiterId: recruiter.id, note: 'Note $step'), EmailStatus.sent);
    }

    final done = (await s.applications.byId(a.id))!;
    expect(done.status, ApplicationStatus.accepted);
    expect((await s.applications.events(a.id)).map((e) => e.status), [
      ApplicationStatus.pending,
      ApplicationStatus.hrInterview,
      ApplicationStatus.technicalInterview,
      ApplicationStatus.accepted,
    ]);

    expect(smtp.messages, hasLength(4));
    expect(smtp.recipients.every((r) => r.contains('etu@x.test')), isTrue);
    final emails = await s.emails.all();
    expect(emails.map((e) => e.status).toSet(), {EmailStatus.sent});
    expect(emails.map((e) => e.subject), containsAll(['Entretien RH : Stage Flutter', 'Entretien technique : Stage Flutter', 'Candidature acceptée : Stage Flutter']));
  });

  test('can be rejected at any open step, then nothing more is allowed', () async {
    final a = await apply();
    await s.applications.moveTo(a.id, ApplicationStatus.hrInterview, recruiterId: recruiter.id);
    await s.applications.moveTo(a.id, ApplicationStatus.rejected, recruiterId: recruiter.id, note: 'Profil trop junior');
    expect((await s.applications.byId(a.id))!.status, ApplicationStatus.rejected);
    expect((await s.emails.all()).first.body, contains('Profil trop junior'));
    expect(smtp.messages, hasLength(3));
    await expectLater(
      s.applications.moveTo(a.id, ApplicationStatus.technicalInterview, recruiterId: recruiter.id),
      throwsA(isA<InvalidTransitionException>()),
    );
  });

  test('steps cannot be skipped', () async {
    final a = await apply();
    for (final target in [ApplicationStatus.technicalInterview, ApplicationStatus.accepted, ApplicationStatus.pending]) {
      await expectLater(s.applications.moveTo(a.id, target, recruiterId: recruiter.id), throwsA(isA<InvalidTransitionException>()));
    }
    expect((await s.applications.byId(a.id))!.status, ApplicationStatus.pending);
    expect(smtp.messages, hasLength(1));
  });

  test('another recruiter cannot move the application', () async {
    final other = await makeUser(s, email: 'o@x.test', fullName: 'Other', role: UserRole.recruiter);
    final a = await apply();
    await expectLater(s.applications.moveTo(a.id, ApplicationStatus.hrInterview, recruiterId: other.id), throwsA(isA<InvalidTransitionException>()));
  });

  test('SMTP not configured: status still changes, email stays queued', () async {
    final local = await makeStage();
    final r = await makeUser(local, email: 'r@x.test', fullName: 'Rec', role: UserRole.recruiter);
    final st = await makeUser(local, email: 's@x.test', fullName: 'Sara', role: UserRole.student);
    final j = await local.jobs.save(recruiterId: r.id, title: 'T', company: 'C', type: JobType.emploi, location: 'L', description: 'D');
    final a = await local.applications.apply(jobId: j.id, student: st, cv: await makeCv(), motivationLetter: letter, message: message);
    expect(await local.applications.moveTo(a.id, ApplicationStatus.hrInterview, recruiterId: r.id), EmailStatus.pending);
    expect((await local.applications.byId(a.id))!.status, ApplicationStatus.hrInterview);
    final emails = await local.emails.all();
    expect(emails, hasLength(2));
    expect(emails.map((e) => e.status).toSet(), {EmailStatus.pending});
    expect(emails.map((e) => e.attempts).toSet(), {0});
    await closeStage(local);
  });

  test('SMTP failure: status kept, email marked failed, sent exactly once after recovery', () async {
    final a = await apply();
    smtp.failing = true;
    expect(await s.applications.moveTo(a.id, ApplicationStatus.hrInterview, recruiterId: recruiter.id), EmailStatus.failed);
    expect((await s.applications.byId(a.id))!.status, ApplicationStatus.hrInterview);
    final failed = (await s.emails.all()).firstWhere((e) => e.status == EmailStatus.failed);
    expect(failed.error, isNotEmpty);

    smtp.failing = false;
    await s.emails.retry(failed.id);
    await s.emails.flush();
    expect(smtp.messages, hasLength(2));
    expect((await s.emails.all()).map((e) => e.status).toSet(), {EmailStatus.sent});
  });

  test('concurrent flushes never send an email twice', () async {
    await s.emails.flush();
    await apply();
    await Future.wait([s.emails.flush(), s.emails.flush(), s.emails.flush()]);
    expect(smtp.messages, hasLength(1));
  });

  test('gives up after the maximum attempts until an admin retries', () async {
    smtp.failing = true;
    final a = await apply();
    for (var i = 0; i < 10; i++) {
      await s.emails.flush();
    }
    final e = (await s.emails.all()).single;
    expect(e.attempts, 5);
    expect(a.status, ApplicationStatus.pending);
  });

  test('student data in the email HTML is escaped', () async {
    await apply();
    expect(smtp.messages.single, isNot(contains('<b>B</b>')));
  });

  test('cannot apply twice, and the duplicate CV is not kept', () async {
    await apply();
    final dir = Directory((await s.applications.byStudent(student.id)).single.cvUrl!).parent;
    final before = dir.listSync().length;
    await expectLater(apply(), throwsA(isA<AlreadyAppliedException>()));
    expect(dir.listSync().length, before);
  });

  test('closed or expired offers refuse applications and leave the feed', () async {
    await s.jobs.setOpen(job.id, false);
    await expectLater(apply(), throwsA(isA<JobClosedException>()));
    expect(await s.jobs.open(), isEmpty);

    await s.jobs.save(id: job.id, recruiterId: recruiter.id, title: 'T', company: 'C', type: JobType.emploi, location: 'L', description: 'D', deadline: DateTime.now().subtract(const Duration(days: 2)));
    await expectLater(apply(), throwsA(isA<JobClosedException>()));
    expect(await s.jobs.open(), isEmpty);
  });

  test('an offer stays open all day on its deadline', () async {
    final today = DateTime.now().copyWith(hour: 0, minute: 0, second: 0);
    await s.jobs.save(id: job.id, recruiterId: recruiter.id, title: 'T', company: 'C', type: JobType.emploi, location: 'L', description: 'D', deadline: today);
    expect(await s.jobs.open(), hasLength(1));
    expect((await apply()).status, ApplicationStatus.pending);
  });

  test('CV validation: extension and size', () async {
    await expectLater(s.applications.apply(jobId: job.id, student: student, cv: await makeCv(name: 'virus.exe'), motivationLetter: letter, message: message), throwsA(isA<CvTypeException>()));
    await expectLater(s.applications.apply(jobId: job.id, student: student, cv: await makeCv(bytes: 5 * 1024 * 1024 + 1), motivationLetter: letter, message: message), throwsA(isA<CvTooLargeException>()));
    expect(await s.applications.byStudent(student.id), isEmpty);
  });

  test('student edits or withdraws only while pending; other students cannot', () async {
    final a = await apply();
    final other = await makeUser(s, email: 'x@x.test', fullName: 'Xena', role: UserRole.student);
    await expectLater(s.applications.withdraw(a.id, other.id), throwsA(isA<ApplicationLockedException>()));

    final newCv = await makeCv(name: 'v2.pdf');
    await s.applications.edit(a.id, studentId: student.id, newCv: newCv, motivationLetter: '$letter Modifiée.', message: message);
    final edited = (await s.applications.byId(a.id))!;
    expect(edited.cvName, 'v2.pdf');
    expect(File(a.cvUrl!).existsSync(), isFalse);

    await s.applications.moveTo(a.id, ApplicationStatus.hrInterview, recruiterId: recruiter.id);
    await expectLater(s.applications.withdraw(a.id, student.id), throwsA(isA<ApplicationLockedException>()));
    await expectLater(s.applications.edit(a.id, studentId: student.id, motivationLetter: letter, message: message), throwsA(isA<ApplicationLockedException>()));
  });

  test('withdraw removes the application and its CV file', () async {
    final a = await apply();
    await s.applications.withdraw(a.id, student.id);
    expect(await s.applications.byId(a.id), isNull);
    expect(File(a.cvUrl!).existsSync(), isFalse);
  });

  test('deleting an offer removes applications and CV files, keeps the email log', () async {
    final a = await apply();
    await s.jobs.delete(job.id);
    expect(await s.applications.byId(a.id), isNull);
    expect(File(a.cvUrl!).existsSync(), isFalse);
    expect(await s.emails.all(), hasLength(1));
  });

  test('deleting a recruiter cascades to offers, applications and CV files', () async {
    final a = await apply();
    await s.deleteUserData(recruiter.id);
    expect(await s.jobs.all(), isEmpty);
    expect(await s.applications.all(), isEmpty);
    expect(File(a.cvUrl!).existsSync(), isFalse);
  });

  test('deleting a student removes the applications and CV, offers stay', () async {
    final a = await apply();
    await s.deleteUserData(student.id);
    expect(await s.applications.all(), isEmpty);
    expect(File(a.cvUrl!).existsSync(), isFalse);
    expect(await s.jobs.all(), hasLength(1));
  });

  test('admin stats reflect the database', () async {
    final a = await apply();
    await s.applications.moveTo(a.id, ApplicationStatus.hrInterview, recruiterId: recruiter.id);
    final stats = await s.adminStats();
    expect((stats.openJobs, stats.totalApplications), (1, 1));
    expect(stats.applicationsByStatus[ApplicationStatus.hrInterview], 1);
    expect(stats.emailsSent, 2);
  });
}
