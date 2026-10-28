import 'package:campusconnect/core/theme/app_theme.dart';
import 'package:campusconnect/models/annonce_model.dart';
import 'package:campusconnect/models/article_model.dart';
import 'package:campusconnect/models/event_model.dart';
import 'package:campusconnect/models/job_offer_model.dart';
import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/providers/annonce_provider.dart';
import 'package:campusconnect/providers/article_provider.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/providers/connectivity_provider.dart';
import 'package:campusconnect/providers/event_provider.dart';
import 'package:campusconnect/providers/job_provider.dart';
import 'package:campusconnect/screens/home/home_screen.dart';
import 'package:campusconnect/screens/profile/profile_screen.dart';
import 'package:campusconnect/widgets/charts/area_line_chart.dart';
import 'package:campusconnect/widgets/featured_card.dart';
import 'package:campusconnect/widgets/filter_chip_pill.dart';
import 'package:campusconnect/widgets/initials_avatar.dart';
import 'package:campusconnect/widgets/sync_chip.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../helpers/authenticated.dart';
import '../helpers/pump_themed.dart';

class _MockArticles extends Mock implements ArticleProvider {}

class _MockAnnonces extends Mock implements AnnonceProvider {}

class _MockEvents extends Mock implements EventProvider {}

class _MockJobs extends Mock implements JobProvider {}

/// Dimanche 18 octobre 2026, 20h30.
final _now = DateTime(2026, 10, 18, 20, 30);

final _offerNew = JobOfferModel(
  id: 'j1',
  recruiterId: 'r',
  companyName: 'Vermeg',
  title: 'Stage développeur Flutter',
  description: '',
  type: JobType.stage,
  location: 'Lac 2',
  requiredSkills: const ['Flutter'],
  postedAt: DateTime(2026, 10, 16),
);

final _offerOld = JobOfferModel(
  id: 'j2',
  recruiterId: 'r2',
  companyName: 'Sofrecom',
  title: 'Ingénieur data junior',
  description: '',
  type: JobType.emploi,
  location: 'Tunis',
  postedAt: DateTime(2026, 9, 1),
);

final _eventThu = EventModel(
  id: 'e1',
  organizerId: 'o',
  organizerName: 'Service carrières',
  title: 'Forum Stages & Emploi',
  description: '',
  category: 'Carrière',
  startDate: DateTime(2026, 10, 22, 14, 0),
  location: 'Amphi A',
  registeredUserIds: const ['x', 'y', 'z'],
);

final _eventFar = EventModel(
  id: 'e2',
  organizerId: 'o',
  organizerName: 'BDE',
  title: 'Gala de fin d\'année',
  description: '',
  category: 'Culture',
  startDate: DateTime(2026, 12, 20, 20, 0),
  location: 'Hall',
  registeredUserIds: const ['uid-1'],
);

final _official = AnnonceModel(
  id: 'n1',
  authorId: 'adm',
  authorName: 'Administration',
  title: 'Bibliothèque fermée le 12 novembre',
  content: '',
  category: 'Officielle',
  isPinned: true,
  createdAt: DateTime(2026, 10, 16, 10),
);

final _noticeOld = AnnonceModel(
  id: 'n2',
  authorId: 'u',
  authorName: 'Yassine',
  title: 'Clés perdues',
  content: '',
  category: 'Perdu & Trouvé',
  createdAt: DateTime(2026, 9, 1),
);

final _article = ArticleModel(
  id: 'a1',
  ownerId: 'u',
  ownerName: 'Amel',
  title: 'Calculatrice graphique',
  description: '',
  price: 45,
  category: 'Fournitures',
  createdAt: DateTime(2026, 10, 1),
);

final _gift = ArticleModel(
  id: 'a2',
  ownerId: 'u',
  ownerName: 'Amel',
  title: 'Livres d\'algèbre L1',
  description: '',
  category: 'Livres',
  createdAt: DateTime(2026, 10, 2),
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
    List<JobOfferModel>? recommended,
  }) {
    when(() => articles.items).thenReturn(a);
    when(() => articles.load()).thenAnswer((_) async {});
    when(() => annonces.items).thenReturn(n);
    when(() => annonces.load()).thenAnswer((_) async {});
    when(() => events.upcoming).thenReturn(e);
    when(() => events.load()).thenAnswer((_) async {});
    when(() => jobs.offers).thenReturn(j);
    when(() => jobs.myApplications).thenReturn(const []);
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

  Future<void> pump(WidgetTester tester,
      {DateTime? now,
      AppUser? user,
      bool emailVerified = true,
      Brightness brightness = Brightness.light,
      double textScale = 1,
      Size size = const Size(420, 1000)}) async {
    await h.signIn(tester, user: user, emailVerified: emailVerified);
    tester.view.physicalSize = size;
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
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            builder: (context, app) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(textScale)),
                child: app!),
            home:
                HomeScreen(onNavigate: navigated.add, now: () => now ?? _now)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('en-tête (maquette)', () {
    testWidgets('first name, greeting by hour, date line and sync pill',
        (tester) async {
      await pump(tester);
      expect(find.text('Bonsoir,'), findsOneWidget);
      expect(find.text('Amel'), findsOneWidget);
      expect(find.text('Dimanche 18 octobre'), findsOneWidget);
      expect(find.text('À jour'), findsOneWidget);
      expect(find.byType(InitialsAvatar), findsOneWidget);
      expect(find.byType(SyncChip), findsOneWidget);
      expect(find.text('Campus'), findsOneWidget);
      expect(find.text('ESPRIT Ghazela'), findsOneWidget);

      await pump(tester, now: DateTime(2026, 10, 19, 9));
      expect(find.text('Bonjour,'), findsOneWidget);
      expect(find.text('Lundi 19 octobre'), findsOneWidget);
    });

    testWidgets('the sync pill reflects the offline queue', (tester) async {
      when(() => h.connectivity.isOnline).thenReturn(false);
      when(() => h.connectivity.pendingActionsCount).thenReturn(2);
      await pump(tester);
      expect(find.text('Hors ligne'), findsOneWidget);

      when(() => h.connectivity.isOnline).thenReturn(true);
      await pump(tester);
      expect(find.text('2 en attente'), findsOneWidget);
    });

    testWidgets(
        'the bell counts this week\'s notices and opens them; the avatar opens the profile',
        (tester) async {
      stub(n: [_official, _noticeOld]);
      await pump(tester);
      expect(find.byKey(const Key('dot')), findsOneWidget);

      await tester.tap(find.byIcon(Icons.notifications_rounded));
      await tester.pump();
      expect(navigated, [HomeTabs.notices]);
      await tester.tap(find.text('AS'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(navigated, [HomeTabs.notices]);
    });

    testWidgets('no badge when nothing is new', (tester) async {
      stub(n: [_noticeOld]);
      await pump(tester);
      expect(find.byKey(const Key('dot')), findsNothing);
      expect(find.text('Aucune nouvelle'), findsOneWidget);
    });
  });

  group('à la une', () {
    testWidgets('shows the pinned official notice first, with author and age',
        (tester) async {
      stub(n: [_noticeOld, _official], e: [_eventThu]);
      await pump(tester);
      final card = find.byType(FeaturedCard);
      expect(card, findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Officiel')),
          findsOneWidget);
      expect(
          find.descendant(
              of: card,
              matching: find.text('Bibliothèque fermée le 12 novembre')),
          findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Administration')),
          findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('il y a 2 jours')),
          findsOneWidget);
      await tester.tap(find.text('Bibliothèque fermée le 12 novembre'));
      await tester.pump();
      expect(navigated, [HomeTabs.notices]);
    });

    testWidgets('then the featured event, reached by swiping', (tester) async {
      stub(n: [_official], e: [_eventThu]);
      await pump(tester);
      await tester.drag(find.byType(FeaturedCard), const Offset(-400, 0));
      await tester.pumpAndSettle();
      final card = find.byType(FeaturedCard);
      expect(find.descendant(of: card, matching: find.text('Carrière')),
          findsOneWidget);
      expect(find.descendant(of: card, matching: find.text("S'inscrire")),
          findsOneWidget);
      await tester.tap(find.descendant(
          of: card, matching: find.text('Forum Stages & Emploi')));
      await tester.pump();
      expect(navigated, [HomeTabs.events]);
    });

    testWidgets('hidden when there is no pinned notice and no event',
        (tester) async {
      stub(n: [_noticeOld]);
      await pump(tester);
      expect(find.byType(FeaturedCard), findsNothing);
    });
  });

  group('modules', () {
    testWidgets('four tiles with real captions, each switching the tab',
        (tester) async {
      stub(
          a: [_article, _gift],
          n: [_official, _noticeOld],
          e: [_eventThu, _eventFar],
          j: [_offerNew, _offerOld]);
      await pump(tester);
      expect(find.text('2 objets'), findsOneWidget);
      expect(find.text('1 nouvelle'), findsOneWidget);
      expect(find.text('1 cette sem.'), findsOneWidget);
      expect(find.text('2 offres'), findsOneWidget);
      expect(find.byType(FilterChipPill), findsNWidgets(4));

      for (final (label, tab) in [
        ('Vente & Don', HomeTabs.market),
        ('Annonces', HomeTabs.notices),
        ('Événements', HomeTabs.events),
        ('Stages', HomeTabs.jobs)
      ]) {
        await tester.tap(find.widgetWithText(FilterChipPill, label));
        await tester.pump();
        expect(navigated.last, tab, reason: label);
      }
    });
  });

  group('complétion du profil', () {
    testWidgets('shows the percentage, what is missing, and opens the profile',
        (tester) async {
      // sampleUser : filière, année, compétences OK ; photo et téléphone manquants ; email vérifié → 4/6
      await pump(tester);
      expect(find.text('67 %'), findsOneWidget);
      expect(find.text('Complète ton profil'), findsOneWidget);
      expect(
          find.text(
              'Ajoute ta photo et ton téléphone pour être visible des recruteurs.'),
          findsOneWidget);
      await tester.tap(find.text('Compléter'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(navigated, isEmpty);
    });

    testWidgets('disappears once the profile is complete', (tester) async {
      await pump(tester,
          user: sampleUser.copyWith(
              photoUrl: 'https://cdn/p.jpg', isPhoneVerified: true));
      expect(find.text('Complète ton profil'), findsNothing);
    });
  });

  group('cette semaine', () {
    testWidgets(
        'features the next event of the week with its date tile, time, place and count',
        (tester) async {
      stub(e: [_eventFar, _eventThu]);
      await pump(tester);
      final week = find.byKey(const Key('week-card'));
      Finder inWeek(String text) =>
          find.descendant(of: week, matching: find.text(text));
      expect(inWeek('JEU'), findsOneWidget);
      expect(inWeek('22'), findsOneWidget);
      expect(inWeek('OCT'), findsOneWidget);
      expect(inWeek('Forum Stages & Emploi'), findsOneWidget);
      expect(inWeek('14:00'), findsOneWidget);
      expect(inWeek('Amphi A'), findsOneWidget);
      expect(inWeek('3 inscrits'), findsOneWidget);
      expect(inWeek('Je participe'), findsOneWidget);
      await tester.ensureVisible(find.text('Agenda'));
      await tester.tap(find.text('Agenda'));
      await tester.pump();
      expect(navigated.last, HomeTabs.events);
    });

    testWidgets('falls back to the next event and marks registration',
        (tester) async {
      stub(e: [_eventFar]);
      await pump(tester);
      final week = find.byKey(const Key('week-card'));
      expect(
          find.descendant(
              of: week, matching: find.text('Gala de fin d\'année')),
          findsOneWidget);
      expect(find.descendant(of: week, matching: find.text('Inscrit')),
          findsOneWidget);
      expect(find.descendant(of: week, matching: find.text('Je participe')),
          findsNothing);
    });
  });

  group('stages pour toi', () {
    testWidgets(
        'recommended offers with their match, "Nouveau" within a week, count in the link',
        (tester) async {
      stub(j: [_offerOld, _offerNew], recommended: [_offerNew]);
      await pump(tester);
      expect(find.text('Tout voir (2)'), findsOneWidget);
      expect(find.text('Stage développeur Flutter'), findsOneWidget);
      expect(find.text('Nouveau'), findsOneWidget);
      expect(find.text('Vermeg · Lac 2'), findsOneWidget);
      expect(find.text('100 % match'), findsOneWidget);
      expect(find.text('Ingénieur data junior'), findsNothing,
          reason: 'seules les recommandées quand il y en a');
    });
  });

  group('vente & don', () {
    testWidgets('a two-column grid with Vente/Don pill, price or Gratuit',
        (tester) async {
      stub(a: [_article, _gift]);
      await pump(tester);
      await tester.ensureVisible(find.text('Calculatrice graphique'));
      expect(find.text('Tout voir (2)'), findsOneWidget);
      expect(find.text('Vente'), findsOneWidget);
      expect(find.text('Don'), findsOneWidget);
      expect(find.text('45 DT'), findsOneWidget);
      expect(find.text('Gratuit'), findsOneWidget);
      await tester.tap(find.text('Calculatrice graphique'));
      await tester.pump();
      expect(navigated.last, HomeTabs.market);
    });

    int columns(WidgetTester tester) =>
        (tester.widget<GridView>(find.byType(GridView)).gridDelegate
                as SliverGridDelegateWithFixedCrossAxisCount)
            .crossAxisCount;

    testWidgets('is two columns at 420 px', (tester) async {
      stub(a: [_article, _gift]);
      await pump(tester);
      expect(columns(tester), 2);
    });

    testWidgets('is three columns at 800 px', (tester) async {
      stub(a: [_article, _gift]);
      await pump(tester, size: const Size(800, 1000));
      expect(columns(tester), 3);
      expect(tester.takeException(), isNull);
    });
  });

  group('activité', () {
    testWidgets('shows the empty text when there is no activity',
        (tester) async {
      await pump(tester);
      await tester.ensureVisible(find.text('Mon activité, 7 jours'));
      expect(find.text('Mon activité, 7 jours'), findsOneWidget);
      expect(find.text('Aucune activité cette semaine'), findsOneWidget);
      expect(find.byType(LineChart), findsNothing);
    });

    testWidgets('draws the chart once the user has published something',
        (tester) async {
      stub(a: [
        ArticleModel(
          id: 'mine',
          ownerId: 'uid-1',
          ownerName: 'Amel',
          title: 'Casque',
          description: '',
          price: 30,
          category: 'Fournitures',
          createdAt: DateTime(2026, 10, 17, 12),
        )
      ]);
      await pump(tester);
      await tester.ensureVisible(find.byType(AreaLineChart));
      expect(find.byType(LineChart), findsOneWidget);
      expect(find.text('Aucune activité cette semaine'), findsNothing);
    });
  });

  group('recherche', () {
    testWidgets('searches loaded content and opens the matching tab',
        (tester) async {
      stub(a: [_article], j: [_offerNew]);
      await pump(tester);
      await tester.tap(find.text('Annonces, objets, stages'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'flutter');
      await tester.pumpAndSettle();
      expect(find.text('Stage développeur Flutter'), findsOneWidget);
      await tester.tap(find.text('Stage développeur Flutter'));
      await tester.pumpAndSettle();
      expect(navigated, [HomeTabs.jobs]);
    });
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('no overflow at 360x640 and text scale $scale, all populated',
        (tester) async {
      when(() => h.connectivity.isOnline).thenReturn(false);
      when(() => h.connectivity.pendingActionsCount).thenReturn(12);
      stub(
          a: [_article, _gift],
          n: [_official, _noticeOld],
          e: [_eventThu, _eventFar],
          j: [_offerNew, _offerOld],
          recommended: [_offerNew]);
      await pump(tester, size: const Size(360, 640), textScale: scale);
      await tester.ensureVisible(find.text('Gratuit'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(AreaLineChart));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('no text under 13 px in ${brightness.name} theme',
        (tester) async {
      stub(
          a: [_article, _gift],
          n: [_official, _noticeOld],
          e: [_eventThu, _eventFar],
          j: [_offerNew, _offerOld],
          recommended: [_offerNew]);
      await pump(tester, brightness: brightness, size: const Size(360, 640));
      expect(tester.takeException(), isNull);
      expectNoSmallText(tester);
    });
  }
}
