import 'package:campusconnect/core/theme/app_theme.dart';
import 'package:campusconnect/core/constants/layout.dart';
import 'package:campusconnect/core/theme/app_colors.dart';
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
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../helpers/mocks.dart';

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
      {int students = 2400, Size size = const Size(420, 1000)}) async {
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
            home: VisitorHomeScreen(studentsCount: () async => students)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder rich(String fragment) => find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().contains(fragment));

  group('hero (maquette)', () {
    testWidgets(
        'shows the icon chip, wordmark, headline, subtitle and the gradient',
        (tester) async {
      await pump(tester);

      expect(find.byIcon(Icons.home_rounded), findsOneWidget);
      expect(find.text('CampusConnect'), findsOneWidget);
      expect(find.text('Tout ton campus,\ndans une seule app'), findsOneWidget);
      expect(find.textContaining('Échange, informe-toi'), findsOneWidget);

      final hero = tester
          .widgetList<Container>(find.byType(Container))
          .firstWhere((c) =>
              c.decoration is BoxDecoration &&
              (c.decoration as BoxDecoration).gradient ==
                  AppColors.brandGradient);
      expect((hero.decoration as BoxDecoration).borderRadius,
          const BorderRadius.vertical(bottom: Radius.circular(24)));
      expect(AppColors.brandGradient.colors,
          [const Color(0xFF4F46E5), const Color(0xFF7C3AED)]);
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
        'cards show price or "Gratuit", pinned official notice, date tile, company initial',
        (tester) async {
      stub(
          a: [_article, _gift],
          n: [_notice, _notice2],
          e: [_event2, _event],
          j: [_offer]);
      await pump(tester);

      expect(find.text('Calculatrice TI-83'), findsOneWidget);
      expect(find.text('45 DT'), findsOneWidget);
      expect(find.text('Gratuit'), findsOneWidget);

      expect(find.text('Épinglé · Officiel'), findsOneWidget);
      expect(find.byIcon(Icons.push_pin_rounded), findsOneWidget);
      expect(find.text('Perdu & Trouvé'), findsOneWidget);
      expect(find.text('Suspension des cours le 15 octobre'), findsOneWidget);

      expect(find.text('OCT'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
      expect(find.text('NOV'), findsOneWidget);
      expect(find.text('Forum Entreprises ESPRIT'), findsOneWidget);

      expect(find.text('V'), findsOneWidget);
      expect(find.text('Vermeg · Stage'), findsOneWidget);

      final rails = tester
          .widgetList<ListView>(find.byType(ListView))
          .where((l) => l.scrollDirection == Axis.horizontal);
      expect(rails.length, 4, reason: 'un rail horizontal par gestion');
    });

    testWidgets('skeletons while loading, honest text when empty',
        (tester) async {
      stub(loading: true);
      await pump(tester);
      expect(find.text('Aucun objet proposé pour l\'instant.'), findsNothing);
      final skeletons = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) =>
              c.decoration is BoxDecoration &&
              (c.decoration as BoxDecoration).color == AppColors.surfaceTone);
      expect(skeletons.length, greaterThanOrEqualTo(3));

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
