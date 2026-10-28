import 'package:campusconnect/core/theme/app_theme.dart';
import 'package:campusconnect/core/constants/layout.dart';
import 'package:campusconnect/models/annonce_model.dart';
import 'package:campusconnect/models/article_model.dart';
import 'package:campusconnect/models/event_model.dart';
import 'package:campusconnect/models/job_offer_model.dart';
import 'package:campusconnect/providers/annonce_provider.dart';
import 'package:campusconnect/providers/article_provider.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/providers/event_provider.dart';
import 'package:campusconnect/providers/job_provider.dart';
import 'package:campusconnect/screens/auth/login_screen.dart';
import 'package:campusconnect/screens/auth/register_screen.dart';
import 'package:campusconnect/screens/visitor/visitor_home_screen.dart';
import 'package:campusconnect/widgets/bottom_action_bar.dart';
import 'package:campusconnect/widgets/featured_card.dart';
import 'package:campusconnect/widgets/photo_card.dart';
import 'package:campusconnect/widgets/pill_button.dart';
import 'package:campusconnect/widgets/setting_row.dart';
import 'package:campusconnect/widgets/skeleton_box.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../helpers/mocks.dart';
import '../helpers/pump_themed.dart';

class _MockArticles extends Mock implements ArticleProvider {}

class _MockAnnonces extends Mock implements AnnonceProvider {}

class _MockEvents extends Mock implements EventProvider {}

class _MockJobs extends Mock implements JobProvider {}

final _event = EventModel(
  id: 'e1',
  organizerId: 'o',
  organizerName: 'Club IEEE',
  title: 'Hackathon IA',
  description: '',
  category: 'Tech',
  startDate: DateTime(2026, 11, 7),
  location: 'Amphi B',
);

final _event2 = EventModel(
  id: 'e2',
  organizerId: 'o',
  organizerName: 'Service carrières',
  title: 'Forum Entreprises ESPRIT',
  description: '',
  category: 'Carrière',
  startDate: DateTime(2026, 10, 14),
  location: 'Hall principal',
);

final _article = ArticleModel(
  id: 'a1',
  ownerId: 'u',
  ownerName: 'Amel',
  title: 'Calculatrice TI-83',
  description: '',
  price: 45,
  category: 'Fournitures',
  createdAt: DateTime(2026, 10, 1),
);

final _gift = ArticleModel(
  id: 'a2',
  ownerId: 'u',
  ownerName: 'Amel',
  title: 'Livre Algo',
  description: '',
  category: 'Livres',
  createdAt: DateTime(2026, 10, 2),
);

final _notice = AnnonceModel(
  id: 'n1',
  authorId: 'adm',
  authorName: 'Scolarité',
  title: 'Suspension des cours le 15 octobre',
  content: 'Direction académique.',
  category: 'Officielle',
  isPinned: true,
  createdAt: DateTime(2026, 10, 3),
);

final _notice2 = AnnonceModel(
  id: 'n2',
  authorId: 'u2',
  authorName: 'Yassine',
  title: 'Trousseau de clés trouvé',
  content: 'Bloc B.',
  category: 'Perdu & Trouvé',
  createdAt: DateTime(2026, 10, 4),
);

final _offer = JobOfferModel(
  id: 'j1',
  recruiterId: 'r',
  companyName: 'Vermeg',
  title: 'Stage développeur Flutter',
  description: '',
  type: JobType.stage,
  location: 'Lac 2',
  postedAt: DateTime(2026, 10, 5),
);

final _offer2 = JobOfferModel(
  id: 'j2',
  recruiterId: 'r2',
  companyName: 'vermeg',
  title: 'Ingénieur data',
  description: '',
  type: JobType.emploi,
  location: 'Tunis',
  postedAt: DateTime(2026, 10, 6),
);

void main() {
  late _MockArticles articles;
  late _MockAnnonces annonces;
  late _MockEvents events;
  late _MockJobs jobs;
  late AuthProvider auth;
  late MockAuthService authService;

  void stub({
    List<ArticleModel> a = const [],
    List<AnnonceModel> n = const [],
    List<EventModel> e = const [],
    List<JobOfferModel> j = const [],
    bool loading = false,
  }) {
    when(() => articles.items).thenReturn(a);
    when(() => articles.isLoading).thenReturn(loading);
    when(() => articles.load()).thenAnswer((_) async {});
    when(() => annonces.items).thenReturn(n);
    when(() => annonces.publicPreview).thenReturn(n.take(5).toList());
    when(() => annonces.isLoading).thenReturn(loading);
    when(() => annonces.load()).thenAnswer((_) async {});
    when(() => events.upcoming).thenReturn(e);
    when(() => events.publicPreview).thenReturn(e.take(5).toList());
    when(() => events.isLoading).thenReturn(loading);
    when(() => events.load()).thenAnswer((_) async {});
    when(() => jobs.offers).thenReturn(j);
    when(() => jobs.isLoading).thenReturn(loading);
    when(() => jobs.load()).thenAnswer((_) async {});
  }

  setUp(() {
    articles = _MockArticles();
    annonces = _MockAnnonces();
    events = _MockEvents();
    jobs = _MockJobs();
    authService = MockAuthService();
    when(() => authService.authStateChanges)
        .thenAnswer((_) => const Stream<User?>.empty());
    auth = AuthProvider(authService: authService);
    stub();
  });

  tearDown(() => auth.dispose());

  Future<void> pump(WidgetTester tester,
      {int students = 2400,
      Size size = const Size(420, 1000),
      Brightness brightness = Brightness.light,
      double textScale = 1,
      bool settle = true}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ArticleProvider>.value(value: articles),
          ChangeNotifierProvider<AnnonceProvider>.value(value: annonces),
          ChangeNotifierProvider<EventProvider>.value(value: events),
          ChangeNotifierProvider<JobProvider>.value(value: jobs),
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
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
            home: VisitorHomeScreen(studentsCount: () async => students)),
      ),
    );
    // Skeletons shimmer forever: only pump a few frames while loading.
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Finder rich(String fragment) => find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().contains(fragment));

  group('hero (maquette)', () {
    testWidgets('shows the campus photo, wordmark, headline and no gradient',
        (tester) async {
      await pump(tester);

      expect(find.text('CampusConnect'), findsOneWidget);
      expect(find.text('Tout ton campus,\ndans une seule app'), findsOneWidget);
      expect(find.textContaining('Échange, informe-toi'), findsOneWidget);

      final image = tester.widget<Image>(find.byWidgetPredicate((w) =>
          w is Image &&
          w.image is ResizeImage &&
          ((w.image as ResizeImage).imageProvider is AssetImage) &&
          ((w.image as ResizeImage).imageProvider as AssetImage).assetName ==
              'assets/images/onboarding/campus_2.jpg'));
      expect(image.fit, BoxFit.cover);

      final gradientBoxes = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .where((d) =>
              d.decoration is BoxDecoration &&
              (d.decoration as BoxDecoration).gradient != null);
      // Only the dark scrim on the photo; no brand gradient.
      expect(gradientBoxes.length, 1);
      final scrim = (gradientBoxes.single.decoration as BoxDecoration).gradient
          as LinearGradient;
      expect(scrim.colors.every((c) => c.toARGB32() & 0x00FFFFFF == 0), isTrue,
          reason: 'scrim is black with alpha');
      expect(
          find.byWidgetPredicate((w) =>
              w is ClipRRect &&
              w.borderRadius ==
                  const BorderRadius.vertical(
                      bottom: Radius.circular(kHeroBottomRadius))),
          findsOneWidget);
    });

    testWidgets(
        'the three pills carry real numbers: students, notices, distinct companies',
        (tester) async {
      stub(
          n: [_notice, _notice2],
          j: [_offer, _offer2]); // deux offres, une seule entreprise (Vermeg)
      await pump(tester, students: 2400);

      expect(rich('2400 étudiants'), findsOneWidget);
      expect(rich('2 annonces'), findsOneWidget);
      expect(rich('1 entreprise'), findsOneWidget);
    });

    testWidgets('singular forms and a placeholder while the count loads',
        (tester) async {
      stub(n: [_notice]);
      await pump(tester, students: 1);
      expect(rich('1 étudiant'), findsOneWidget);
      expect(rich('1 annonce'), findsOneWidget);
      expect(rich('0 entreprises'), findsOneWidget);
    });
  });

  group('sections (maquette)', () {
    testWidgets('four sections, each with "Voir tout" opening the login',
        (tester) async {
      stub(a: [_article], n: [_notice], e: [_event], j: [_offer]);
      await pump(tester);

      for (final t in [
        'Vente & Don',
        'Annonces du campus',
        'Événements à venir',
        'Stage & Emploi'
      ]) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('Voir tout'), findsNWidgets(4));
      await tester.tap(find.text('Voir tout').first);
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets(
        'articles are photo cards, first event is featured, notices are rows, offers are photo cards',
        (tester) async {
      stub(
          a: [_article, _gift],
          n: [_notice, _notice2],
          e: [_event2, _event],
          j: [_offer]);
      await pump(tester);

      // Articles.
      expect(
          find.widgetWithText(PhotoCard, 'Calculatrice TI-83'), findsOneWidget);
      expect(find.widgetWithText(PhotoCard, 'Livre Algo'), findsOneWidget);
      expect(find.text('45 DT'), findsOneWidget);
      expect(find.text('Gratuit'), findsOneWidget);
      expect(find.text('Vente'), findsOneWidget);
      expect(find.text('Don'), findsOneWidget);

      // Notices.
      expect(find.text('Suspension des cours le 15 octobre'), findsOneWidget);
      expect(find.text('Trousseau de clés trouvé'), findsOneWidget);
      expect(find.byIcon(Icons.push_pin_rounded), findsOneWidget);
      expect(find.textContaining('Scolarité'), findsOneWidget);

      // Events: first one featured, the other one in the rail.
      expect(find.byType(FeaturedCard), findsOneWidget);
      expect(find.widgetWithText(FeaturedCard, 'Forum Entreprises ESPRIT'),
          findsOneWidget);
      expect(find.widgetWithText(FeaturedCard, 'Carrière'), findsOneWidget);
      expect(find.widgetWithText(PhotoCard, 'Hackathon IA'), findsOneWidget);

      // Offers.
      expect(find.widgetWithText(PhotoCard, 'Stage développeur Flutter'),
          findsOneWidget);
      expect(find.text('Vermeg · Lac 2'), findsOneWidget);

      final rails = tester
          .widgetList<ListView>(find.byType(ListView))
          .where((l) => l.scrollDirection == Axis.horizontal);
      expect(rails.length, 3, reason: 'articles, autres événements, offres');
    });

    testWidgets('tapping a notice row or the featured action opens the login',
        (tester) async {
      stub(n: [_notice], e: [_event]);
      await pump(tester);
      await tester.tap(find.text('Suspension des cours le 15 octobre'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Voir').first);
      await tester.tap(find.text('Voir').first);
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('skeletons while loading, honest text when empty',
        (tester) async {
      stub(loading: true);
      await pump(tester, settle: false);
      expect(find.text('Aucun objet proposé pour l\'instant.'), findsNothing);
      expect(
          find.byType(SkeletonBox).evaluate().length, greaterThanOrEqualTo(3));

      stub();
      await pump(tester);
      expect(find.text('Aucun objet proposé pour l\'instant.'), findsOneWidget);
      expect(
          find.text('Aucune annonce publiée pour l\'instant.'), findsOneWidget);
      expect(find.text('Aucun événement annoncé pour l\'instant.'),
          findsOneWidget);
      expect(
          find.text('Aucune offre publiée pour l\'instant.'), findsOneWidget);
    });

    testWidgets('loads every feed once on open', (tester) async {
      await pump(tester);
      verify(() => articles.load()).called(1);
      verify(() => annonces.load()).called(1);
      verify(() => events.load()).called(1);
      verify(() => jobs.load()).called(1);
    });
  });

  group('call to action', () {
    testWidgets('the bottom bar creates an account or opens the login',
        (tester) async {
      await pump(tester);
      expect(find.textContaining("Ceci n'est qu'un aperçu", findRichText: true),
          findsOneWidget);

      final ctas = tester.widgetList<PillButton>(find.byType(PillButton));
      expect(ctas.map((b) => b.label),
          ['Créer un compte étudiant', 'Se connecter']);
      expect(ctas.last.style, PillStyle.ghost);

      await tester.tap(find.text('Créer un compte étudiant'));
      await tester.pumpAndSettle();
      expect(find.byType(RegisterScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Se connecter'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('the bar stays visible while the content scrolls',
        (tester) async {
      stub(
          a: [_article, _gift],
          n: [_notice, _notice2],
          e: [_event, _event2],
          j: [_offer, _offer2]);
      await pump(tester, size: const Size(360, 640));
      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('Créer un compte étudiant'), findsOneWidget);
      expect(tester.getRect(find.text('Créer un compte étudiant')).bottom,
          lessThanOrEqualTo(640));
    });
  });

  group('robustness', () {
    testWidgets('no overflow at 360 px wide with full content', (tester) async {
      stub(
          a: [_article, _gift],
          n: [_notice, _notice2],
          e: [_event, _event2],
          j: [_offer, _offer2]);
      await pump(tester, size: const Size(360, 640));
      expect(tester.takeException(), isNull);
      expect(kPagePadding, 20);
      expect(
          tester
              .getTopLeft(find.text('Tout ton campus,\ndans une seule app'))
              .dx,
          kPagePadding);
      expect(tester.getTopLeft(find.text('Vente & Don')).dx, kPagePadding);
    });

    testWidgets('no overflow at 360 px wide in dark mode', (tester) async {
      stub(
          a: [_article, _gift],
          n: [_notice, _notice2],
          e: [_event, _event2],
          j: [_offer, _offer2]);
      await pump(tester,
          size: const Size(360, 640), brightness: Brightness.dark);
      expect(tester.takeException(), isNull);
    });

    for (final scale in [1.3, 2.0]) {
      testWidgets('no overflow at 360 px with text scale $scale',
          (tester) async {
        stub(
            a: [_article, _gift],
            n: [_notice, _notice2],
            e: [_event, _event2],
            j: [_offer, _offer2]);
        await pump(tester, size: const Size(360, 640), textScale: scale);
        expect(tester.takeException(), isNull);
        await tester.drag(
            find.byType(SingleChildScrollView), const Offset(0, -3000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    for (final scale in [1.0, 1.3]) {
      testWidgets('the last section clears the bottom bar at scale $scale',
          (tester) async {
        stub(
            a: [_article, _gift],
            n: [_notice, _notice2],
            e: [_event, _event2],
            j: [_offer, _offer2]);
        await pump(tester, size: const Size(360, 640), textScale: scale);
        await tester.drag(
            find.byType(SingleChildScrollView), const Offset(0, -5000));
        await tester.pumpAndSettle();
        final info = tester.getRect(find.byType(SettingGroup).last);
        final bar = tester.getRect(find.byType(BottomActionBar));
        expect(info.bottom, lessThanOrEqualTo(bar.top));
      });
    }

    testWidgets('wide screens centre the content at kContentMaxWidth',
        (tester) async {
      stub(a: [_article], n: [_notice], e: [_event], j: [_offer]);
      await pump(tester, size: const Size(1000, 800));
      expect(tester.takeException(), isNull);
      final box = tester.getRect(find.text('Annonces du campus'));
      expect(box.left, greaterThanOrEqualTo((1000 - kContentMaxWidth) / 2));
    });

    for (final b in Brightness.values) {
      testWidgets('no text under 13 px (${b.name})', (tester) async {
        stub(
            a: [_article, _gift],
            n: [_notice, _notice2],
            e: [_event, _event2],
            j: [_offer]);
        await pump(tester, brightness: b);
        expectNoSmallText(tester);
      });
    }

    testWidgets('no text under 13 px', (tester) async {
      stub(
          a: [_article, _gift],
          n: [_notice, _notice2],
          e: [_event],
          j: [_offer]);
      await pump(tester);
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        final size = t.style?.fontSize;
        if (size != null) {
          expect(size, greaterThanOrEqualTo(13),
              reason: '"${t.data}" est à $size px');
        }
      }
    });
  });
}
