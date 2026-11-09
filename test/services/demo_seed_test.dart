import 'dart:io';

import 'package:campusconnect/core/constants/app_constants.dart';
import 'package:campusconnect/core/utils/password_hasher.dart';
import 'package:campusconnect/models/event_model.dart';
import 'package:campusconnect/models/job_offer_model.dart';
import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/providers/annonce_provider.dart';
import 'package:campusconnect/providers/job_provider.dart';
import 'package:campusconnect/services/auth_service.dart';
import 'package:campusconnect/services/demo_seed.dart';
import 'package:campusconnect/services/local_store.dart';
import 'package:campusconnect/services/user_stats_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/local_db.dart';

void main() {
  final now = DateTime.utc(2026, 11, 9, 12);
  late LocalStore store;

  DemoSeed seed() => DemoSeed(store: store, hasher: PasswordHasher(iterations: 1000), clock: () => now);

  List<AppUser> users() => [for (final d in store.all(AppConstants.usersCollection)) AppUser.fromMap(d.id, d.data)];

  setUp(() async {
    await openTestDatabase();
    store = LocalStore();
  });
  tearDown(closeTestDatabase);

  test('the 6 demo accounts log in through AuthService with Campus2026!', () async {
    await seed().ensureSeeded();
    final auth = AuthService(store: store, clock: () => now);
    const expected = {
      'admin@esprit.tn': UserRole.admin,
      'amel@esprit.tn': UserRole.student,
      'sarra@esprit.tn': UserRole.student,
      'youssef@esprit.tn': UserRole.student,
      'recruteur@vermeg.tn': UserRole.recruiter,
      'jawher@esprit.tn': UserRole.student,
    };
    for (final MapEntry(key: email, value: role) in expected.entries) {
      final account = await auth.signInWithEmail(email, DemoSeed.password);
      expect(account.email, email);
      final profile = await auth.fetchProfile(account.uid);
      expect(profile!.role, role, reason: email);
      await auth.signOut();
    }
    await expectLater(auth.signInWithEmail('admin@esprit.tn', 'mauvais'), throwsA(anything));
  });

  test('profiles: verified admin, pending cards on the bundled photo, Jawher complete', () async {
    await seed().ensureSeeded();
    AppUser user(String id) => AppUser.fromMap(id, store.get(AppConstants.usersCollection, id)!);

    expect(user(DemoSeed.adminId).isVerifiedStudent, isTrue);
    for (final id in [DemoSeed.amelId, DemoSeed.sarraId, DemoSeed.youssefId]) {
      expect(user(id).isVerifiedStudent, isFalse);
      expect(user(id).studentCard.status, StudentCardStatus.pending);
      expect(user(id).studentCard.imagePath, 'asset:assets/images/cover_campus.jpg');
      expect(user(id).skills, ['Flutter', 'Firebase']);
    }
    expect(user(DemoSeed.recruiterId).studentCard.status, StudentCardStatus.none);

    final jawher = user(DemoSeed.jawherId);
    expect(jawher.isVerifiedStudent, isTrue);
    expect(jawher.major, 'Génie Informatique');
    expect(jawher.year, '4SIM2');
    expect(jawher.skills, ['Flutter', 'Firebase', 'Dart', 'UI/UX', 'Git']);
    expect(jawher.studentCard.status, StudentCardStatus.verified);
    expect(jawher.studentCard.reviewedBy, DemoSeed.adminId);
    expect(jawher.createdAt.year, 2024);

    // Les comptes fictifs n'ont pas d'identifiants de connexion.
    expect(store.all(AuthService.accountsCollection), hasLength(6));
  });

  test('admin analytics: 1 248 sign-ups in 30 days (+12 %), 37 pending cards, 77/17/6 %', () async {
    await seed().ensureSeeded();
    final all = users();
    final stats = aggregate(all, now: now.toLocal(), days: 30);
    expect(stats.signUps, 1248);
    expect(stats.changePercent, closeTo(12, 0.5));
    expect(stats.pendingCards, 37);
    double share(UserRole r) => stats.byRole[r]! / all.length * 100;
    expect(share(UserRole.student), closeTo(77, 1));
    expect(share(UserRole.recruiter), closeTo(17, 1));
    expect(share(UserRole.admin), closeTo(6, 1));
  });

  test('content: events, annonces, offers and Jawher\'s applications', () async {
    await seed().ensureSeeded();

    final events = [for (final d in store.all(AppConstants.eventsCollection)) EventModel.fromMap(d.id, d.data)];
    expect(events, hasLength(5));
    final hackathon = events.singleWhere((e) => e.id == 'demo-hackathon');
    expect(hackathon.startDate.isAfter(now), isTrue, reason: 'reporté au samedi suivant');
    expect(hackathon.startDate.weekday, DateTime.saturday);
    expect(hackathon.registeredUserIds, hasLength(3 + 85));
    expect(hackathon.posterUrl, 'asset:assets/images/onboarding/esprit_team.jpg');

    final annonces = AnnonceProvider(store: store);
    await annonces.load();
    expect(annonces.items, hasLength(14));
    expect(annonces.items.take(2).every((a) => a.isPinned && a.category == 'Officielle'), isTrue);
    expect(annonces.items.where((a) => a.authorId == DemoSeed.jawherId), hasLength(12));

    final jobs = JobProvider(store: store);
    await jobs.load();
    expect(jobs.offers, hasLength(6));
    expect(jobs.offers.where((o) => o.type == JobType.emploi), hasLength(2));
    await jobs.loadMyApplications(DemoSeed.jawherId);
    expect(jobs.myApplications.map((a) => a.status), [
      ApplicationStatus.sent,
      ApplicationStatus.seen,
      ApplicationStatus.accepted,
    ]);
  });

  test('a second call is a no-op', () async {
    await seed().ensureSeeded();
    await store.update(AppConstants.usersCollection, DemoSeed.amelId, {'fullName': 'Amel modifiée'});
    await store.delete(AppConstants.annoncesCollection, 'demo-officielle-examens');
    final count = store.all(AppConstants.usersCollection).length;

    await seed().ensureSeeded();

    expect(store.all(AppConstants.usersCollection), hasLength(count));
    expect(store.get(AppConstants.usersCollection, DemoSeed.amelId)!['fullName'], 'Amel modifiée');
    expect(store.exists(AppConstants.annoncesCollection, 'demo-officielle-examens'), isFalse);
  });

  test('does nothing when users already exist', () async {
    await store.set(AppConstants.usersCollection, 'u1', {'fullName': 'Déjà là'});
    await seed().ensureSeeded();
    expect(store.all(AppConstants.usersCollection), hasLength(1));
    expect(store.all(AuthService.accountsCollection), isEmpty);
    expect(store.all(AppConstants.eventsCollection), isEmpty);
  });

  test('everything is in SQLite once ensureSeeded returns', () async {
    final dir = await Directory.systemTemp.createTemp('demo_seed');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/campusconnect.db';
    await openTestDatabase(path: path);
    store = LocalStore();

    final watch = Stopwatch()..start();
    await seed().ensureSeeded();
    watch.stop();
    final count = store.all(AppConstants.usersCollection).length;
    expect(count, greaterThan(2000));
    expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
    // ignore: avoid_print
    print('DemoSeed : $count comptes écrits en ${watch.elapsedMilliseconds} ms');

    final reloaded = await openTestDatabase(path: path); // ferme puis rouvre
    expect(reloaded.readCollection(AppConstants.usersCollection), hasLength(count));
    expect(reloaded.readCollection(AuthService.accountsCollection), hasLength(6));
  });
}
