import 'package:campusconnect/core/theme/app_theme.dart';
import 'package:campusconnect/core/theme/app_colors.dart';
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
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../helpers/authenticated.dart';

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

      await pump(tester, now: DateTime(2026, 10, 19, 9));
      expect(find.text('Bonjour,'), findsOneWidget);
      expect(find.text('Lundi 19 octobre'), findsOneWidget);
    });

    testWidgets('the sync pill reflects the offline queue', (tester) async {
      when(() => h.connectivity.isOnline).thenReturn(false);
      when(() => h.connectivity.pendingActionsCount).thenReturn(2);
      await pump(tester);
      expect(find.text('Hors-ligne · 2 en attente'), findsOneWidget);
    });

    testWidgets(
        'the bell counts this week\'s notices and opens them; the avatar opens the profile',
        (tester) async {
      stub(n: [_official, _noticeOld]);
      await pump(tester);
      expect(find.byKey(const Key('bell-badge')), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('bell-badge')),
              matching: find.text('1')),
          findsOneWidget);

      await tester.tap(find.byIcon(Icons.notifications_none_rounded));
      await tester.pump();
      await tester.tap(find.text('AS'));
      await tester.pump();
      expect(navigated, [HomeTabs.notices, HomeTabs.profile]);
    });

    testWidgets('no badge when nothing is new', (tester) async {
      stub(n: [_noticeOld]);
      await pump(tester);
      expect(find.byKey(const Key('bell-badge')), findsNothing);
      expect(find.text('Aucune nouvelle'), findsOneWidget);
    });
  });

  group('annonce officielle', () {
    testWidgets(
        'the pinned official notice is featured with its author and age',
        (tester) async {
      stub(n: [_noticeOld, _official]);
      await pump(tester);
      expect(find.text('Officiel · Épinglé'), findsOneWidget);
      expect(find.text('Bibliothèque fermée le 12 novembre'), findsOneWidget);
      expect(find.text('Administration · il y a 2 jours'), findsOneWidget);
      await tester.tap(find.text('Bibliothèque fermée le 12 novembre'));
      await tester.pump();
      expect(navigated, [HomeTabs.notices]);
    });

    testWidgets('hidden when there is no pinned official notice',
        (tester) async {
      stub(n: [_noticeOld]);
      await pump(tester);
      expect(find.text('Officiel · Épinglé'), findsNothing);
    });
  });

  group('accès rapide', () {
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
      final red = tester.widget<Text>(find.text('1 nouvelle')).style!.color;
      expect(red, AppColors.homeDanger);

      for (final (label, tab) in [
        ('Annonces', HomeTabs.notices),
        ('Événements', HomeTabs.events),
        ('Stages', HomeTabs.jobs)
      ]) {
        await tester.tap(find.text(label).first);
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
      expect(find.text('67%'), findsOneWidget);
      expect(find.text('Complète ton profil'), findsOneWidget);
      expect(
          find.text(
              'Ajoute ta photo et ton téléphone pour être visible des recruteurs.'),
          findsOneWidget);
      await tester.tap(find.text('Compléter'));
      await tester.pump();
      expect(navigated, [HomeTabs.profile]);
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
      expect(find.text('JEU'), findsOneWidget);
      expect(find.text('22'), findsOneWidget);
      expect(find.text('OCT'), findsOneWidget);
      expect(find.text('Forum Stages & Emploi'), findsOneWidget);
      expect(find.text('14:00'), findsOneWidget);
      expect(find.text('Amphi A'), findsOneWidget);
      expect(find.text('3 inscrits'), findsOneWidget);
      expect(find.text('Je participe'), findsOneWidget);
      await tester.tap(find.text('Agenda'));
      await tester.pump();
      expect(navigated.last, HomeTabs.events);
    });

    testWidgets('falls back to the next event and marks registration',
        (tester) async {
      stub(e: [_eventFar]);
      await pump(tester);
      expect(find.text('Gala de fin d\'année'), findsOneWidget);
      expect(find.text('Inscrit'), findsOneWidget);
    });
  });

  group('stages pour toi', () {
    testWidgets(
        'recommended offers first, "Nouveau" within a week, count in the link',
        (tester) async {
      stub(j: [_offerOld, _offerNew], recommended: [_offerNew]);
      await pump(tester);
      expect(find.text('Tout voir (2)'), findsOneWidget);
      expect(find.text('Stage développeur Flutter'), findsOneWidget);
      expect(find.text('Nouveau'), findsOneWidget);
      expect(find.text('Vermeg · Lac 2 · Stage'), findsOneWidget);
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
  });

  group('recherche', () {
    testWidgets('searches loaded content and opens the matching tab',
        (tester) async {
      stub(a: [_article], j: [_offerNew]);
      await pump(tester);
      await tester.tap(find.text('Annonces, objets, stages…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'flutter');
      await tester.pumpAndSettle();
      expect(find.text('Stage développeur Flutter'), findsOneWidget);
      await tester.tap(find.text('Stage développeur Flutter'));
      await tester.pumpAndSettle();
      expect(navigated, [HomeTabs.jobs]);
    });
  });

  testWidgets(
      'no overflow at 360 px and no text under 13 px, with everything populated',
      (tester) async {
    when(() => h.connectivity.isOnline).thenReturn(false);
    when(() => h.connectivity.pendingActionsCount).thenReturn(12);
    stub(
        a: [_article, _gift],
        n: [_official, _noticeOld],
        e: [_eventThu, _eventFar],
        j: [_offerNew, _offerOld],
        recommended: [_offerNew]);
    await pump(tester, size: const Size(360, 640));
    await tester.ensureVisible(find.text('Gratuit'));
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
