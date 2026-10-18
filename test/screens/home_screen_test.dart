import 'package:campusconnect/models/annonce_model.dart';
import 'package:campusconnect/models/article_model.dart';
import 'package:campusconnect/models/event_model.dart';
import 'package:campusconnect/models/job_offer_model.dart';
import 'package:campusconnect/providers/annonce_provider.dart';
import 'package:campusconnect/providers/article_provider.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/providers/connectivity_provider.dart';
import 'package:campusconnect/providers/event_provider.dart';
import 'package:campusconnect/providers/job_provider.dart';
import 'package:campusconnect/screens/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../helpers/authenticated.dart';

class _MockArticles extends Mock implements ArticleProvider {}

class _MockAnnonces extends Mock implements AnnonceProvider {}

class _MockEvents extends Mock implements EventProvider {}

class _MockJobs extends Mock implements JobProvider {}

final _now = DateTime(2026, 10, 18, 14, 30);

final _offer = JobOfferModel(
  id: 'j1',
  recruiterId: 'r',
  companyName: 'Vermeg',
  title: 'Stage développeur Flutter',
  description: '',
  type: JobType.stage,
  location: 'Lac 2',
  requiredSkills: const ['Flutter'],
  postedAt: DateTime(2026, 10, 5),
);

final _application = ApplicationModel(
  id: 'ap1',
  jobOfferId: 'j1',
  jobTitle: 'Stage développeur Flutter',
  companyName: 'Vermeg',
  candidateId: 'uid-1',
  status: ApplicationStatus.seen,
  appliedAt: DateTime(2026, 10, 18, 9, 30),
);

final _eventTomorrow = EventModel(
  id: 'e1',
  organizerId: 'o',
  organizerName: 'Club IA',
  title: 'Conférence IA',
  description: '',
  category: 'Tech',
  startDate: DateTime(2026, 10, 19, 14, 0),
  location: 'Amphi A',
  registeredUserIds: const ['uid-1'],
);

final _eventNextMonth = EventModel(
  id: 'e2',
  organizerId: 'o',
  organizerName: 'BDE',
  title: 'Gala',
  description: '',
  category: 'Culture',
  startDate: DateTime(2026, 11, 20, 20, 0),
  location: 'Hall',
);

final _official = AnnonceModel(
  id: 'n1',
  authorId: 'adm',
  authorName: 'Scolarité',
  title: 'Suspension des cours le 15 octobre',
  content: '',
  category: 'Officielle',
  isPinned: true,
  createdAt: DateTime(2026, 10, 17, 10),
);

final _article = ArticleModel(
  id: 'a1',
  ownerId: 'u',
  ownerName: 'Amel',
  title: 'Calculatrice TI-84',
  description: '',
  price: 45,
  category: 'Fournitures',
  createdAt: DateTime(2026, 10, 1),
);

void main() {
  late AuthHarness h;
  late _MockArticles articles;
  late _MockAnnonces annonces;
  late _MockEvents events;
  late _MockJobs jobs;
  late List<int> navigated;

  void stub({
    List<ArticleModel> a = const [],
    List<AnnonceModel> n = const [],
    List<EventModel> e = const [],
    List<JobOfferModel> j = const [],
    List<ApplicationModel> apps = const [],
    List<JobOfferModel>? recommended,
  }) {
    when(() => articles.items).thenReturn(a);
    when(() => articles.load()).thenAnswer((_) async {});
    when(() => annonces.items).thenReturn(n);
    when(() => annonces.load()).thenAnswer((_) async {});
    when(() => events.upcoming).thenReturn(e);
    when(() => events.load()).thenAnswer((_) async {});
    when(() => jobs.offers).thenReturn(j);
    when(() => jobs.myApplications).thenReturn(apps);
    when(() => jobs.recommendedFor(any())).thenReturn(recommended ?? const []);
    when(() => jobs.load()).thenAnswer((_) async {});
    when(() => jobs.loadMyApplications(any())).thenAnswer((_) async {});
  }

  setUp(() {
    h = AuthHarness();
    articles = _MockArticles();
    annonces = _MockAnnonces();
    events = _MockEvents();
    jobs = _MockJobs();
    navigated = [];
    stub();
  });
  tearDown(() => h.dispose());

  Future<void> pump(WidgetTester tester, {DateTime? now}) async {
    await h.signIn(tester);
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: h.provider),
          ChangeNotifierProvider<ConnectivityProvider>.value(
              value: h.connectivity),
          ChangeNotifierProvider<ArticleProvider>.value(value: articles),
          ChangeNotifierProvider<AnnonceProvider>.value(value: annonces),
          ChangeNotifierProvider<EventProvider>.value(value: events),
          ChangeNotifierProvider<JobProvider>.value(value: jobs),
        ],
        child: MaterialApp(
          home: HomeScreen(onNavigate: navigated.add, now: () => now ?? _now),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('header', () {
    testWidgets('greets by time of day and shows the student', (tester) async {
      await pump(tester, now: DateTime(2026, 10, 18, 9));
      expect(find.text('Bonjour'), findsOneWidget);
      expect(find.text('Amel Ben Salah'), findsOneWidget);
      expect(find.text('AS'), findsOneWidget);

      await pump(tester, now: DateTime(2026, 10, 18, 15));
      expect(find.text('Bon après-midi'), findsOneWidget);
      await pump(tester, now: DateTime(2026, 10, 18, 21));
      expect(find.text('Bonsoir'), findsOneWidget);
    });

    testWidgets('the avatar opens the profile tab', (tester) async {
      await pump(tester);
      await tester.tap(find.text('AS'));
      await tester.pump();
      expect(navigated, [HomeTabs.profile]);
    });

    testWidgets('loads the feeds and the student\'s applications once',
        (tester) async {
      await pump(tester);
      verify(() => jobs.loadMyApplications('uid-1')).called(1);
      verify(() => articles.load()).called(1);
      verify(() => events.load()).called(1);
    });
  });

  group('modules', () {
    testWidgets('each card switches the tab instead of pushing a screen',
        (tester) async {
      await pump(tester);
      for (final (label, tab) in [
        ('Mon profil', HomeTabs.profile),
        ('Vente & Don', HomeTabs.market),
        ('Annonces', HomeTabs.notices),
        ('Événements', HomeTabs.events),
        ('Stage & Emploi', HomeTabs.jobs),
      ]) {
        await tester.tap(find.text(label));
        await tester.pump();
        expect(navigated.last, tab, reason: label);
      }
      expect(find.byType(Navigator), findsOneWidget);
    });

    testWidgets(
        'captions carry real counts; the notices dot appears for a pinned official notice',
        (tester) async {
      stub(
          a: [_article],
          n: [_official],
          e: [_eventTomorrow, _eventNextMonth],
          j: [_offer]);
      await pump(tester);

      expect(find.text('1 objet'), findsOneWidget);
      expect(find.text('1 annonce'), findsOneWidget);
      expect(find.text('1 cette semaine'), findsOneWidget);
      expect(find.byKey(const Key('module-dot')), findsOneWidget);
      expect(find.text('1 offre disponible'), findsOneWidget);
      expect(find.text('À compléter : photo'), findsOneWidget); // sampleUser a une filière et une compétence
    });

    testWidgets('the jobs card says how many offers match the profile',
        (tester) async {
      stub(j: [_offer], recommended: [_offer]);
      await pump(tester);
      expect(find.text('1 offre correspond à votre profil'), findsOneWidget);
      verify(() => jobs.recommendedFor(['Flutter'])).called(greaterThan(0));
    });

    testWidgets('no dot and honest captions when the campus is empty',
        (tester) async {
      await pump(tester);
      expect(find.byKey(const Key('module-dot')), findsNothing);
      expect(find.text('Rien cette semaine'), findsOneWidget);
      expect(find.text('Aucune offre pour l\'instant'), findsOneWidget);
    });
  });

  group('activité récente', () {
    testWidgets(
        'lists the application status, the next registered event and the official notice',
        (tester) async {
      stub(
          n: [_official],
          e: [_eventNextMonth, _eventTomorrow],
          apps: [_application]);
      await pump(tester);

      expect(
          find.text('Votre candidature chez Vermeg a été vue'), findsOneWidget);
      expect(find.text('il y a 5 h'), findsOneWidget);
      expect(find.text('Rappel : Conférence IA'), findsOneWidget);
      expect(find.text('demain à 14h00'), findsOneWidget);
      expect(find.text('Suspension des cours le 15 octobre'), findsOneWidget);
      expect(find.text('Annonce officielle · hier'), findsOneWidget);

      await tester.tap(find.text('Rappel : Conférence IA'));
      await tester.pump();
      expect(navigated.last, HomeTabs.events);
    });

    testWidgets(
        'events the student is not registered to do not produce a reminder',
        (tester) async {
      stub(e: [_eventNextMonth]);
      await pump(tester);
      expect(find.textContaining('Rappel'), findsNothing);
      expect(find.textContaining('Rien de nouveau'), findsOneWidget);
    });

    testWidgets('"Explorer" in the empty state opens the events tab',
        (tester) async {
      await pump(tester);
      await tester.tap(find.text('Explorer'));
      await tester.pump();
      expect(navigated, [HomeTabs.events]);
    });
  });

  group('recherche', () {
    testWidgets('searches across loaded content and opens the matching tab',
        (tester) async {
      stub(a: [_article], j: [_offer]);
      await pump(tester);

      await tester.tap(find.text('Rechercher sur CampusConnect…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'flutter');
      await tester.pumpAndSettle();

      expect(find.text('Stage développeur Flutter'), findsOneWidget);
      expect(find.text('Calculatrice TI-84'), findsNothing);

      await tester.tap(find.text('Stage développeur Flutter'));
      await tester.pumpAndSettle();
      expect(navigated, [HomeTabs.jobs]);
    });

    testWidgets('says when nothing matches', (tester) async {
      stub(a: [_article]);
      await pump(tester);
      await tester.tap(find.text('Rechercher sur CampusConnect…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('Aucun résultat pour « zzz ».'), findsOneWidget);
    });
  });

  testWidgets('no text under 13 px and no overflow at 360 px', (tester) async {
    stub(
        a: [_article],
        n: [_official],
        e: [_eventTomorrow],
        j: [_offer],
        apps: [_application]);
    await h.signIn(tester);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: h.provider),
          ChangeNotifierProvider<ConnectivityProvider>.value(
              value: h.connectivity),
          ChangeNotifierProvider<ArticleProvider>.value(value: articles),
          ChangeNotifierProvider<AnnonceProvider>.value(value: annonces),
          ChangeNotifierProvider<EventProvider>.value(value: events),
          ChangeNotifierProvider<JobProvider>.value(value: jobs),
        ],
        child: MaterialApp(
            home: HomeScreen(onNavigate: navigated.add, now: () => _now)),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      final size = t.style?.fontSize;
      if (size != null) {
        expect(size, greaterThanOrEqualTo(13),
            reason: '"${t.data}" est à $size px');
      }
    }
  });
}
