import 'package:campusconnect/core/constants/layout.dart';
import 'package:campusconnect/core/theme/app_colors.dart';
import 'package:campusconnect/core/theme/module_colors.dart';
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

final _article = ArticleModel(
  id: 'a1',
  ownerId: 'u',
  ownerName: 'Amel',
  title: 'Calculatrice TI-83',
  description: '',
  price: 120,
  category: 'Fournitures',
  createdAt: DateTime(2026, 10, 1),
);

final _gift = ArticleModel(
  id: 'a2',
  ownerId: 'u',
  ownerName: 'Amel',
  title: 'Manuel d\'analyse',
  description: '',
  category: 'Livres',
  createdAt: DateTime(2026, 10, 2),
);

final _notice = AnnonceModel(
  id: 'n1',
  authorId: 'adm',
  authorName: 'Scolarité',
  title: 'Fermeture de la bibliothèque le 12',
  content: 'Travaux de rénovation au 2e étage.',
  category: 'Officielle',
  isPinned: true,
  createdAt: DateTime(2026, 10, 3),
);

final _notice2 = AnnonceModel(
  id: 'n2',
  authorId: 'u2',
  authorName: 'Yassine',
  title: 'Clés perdues près du parking',
  content: 'Trousseau avec porte-clés bleu.',
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

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1000);
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
        child: const MaterialApp(home: VisitorHomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  final gradients = find.byWidgetPredicate((w) =>
      w is Container &&
      w.decoration is BoxDecoration &&
      (w.decoration as BoxDecoration).gradient != null);
  final shadows = find.byWidgetPredicate((w) =>
      w is Container &&
      w.decoration is BoxDecoration &&
      (w.decoration as BoxDecoration).boxShadow != null);
  final hairlines = find.byWidgetPredicate((w) =>
      w is Container &&
      w.decoration is BoxDecoration &&
      (w.decoration as BoxDecoration).border != null);

  group('first screen', () {
    testWidgets(
        'says what it is, in large type, with one real action and the login link',
        (tester) async {
      await pump(tester);

      final headline = tester.widget<Text>(find.text('Le campus,\nen direct.'));
      final theme = Theme.of(tester.element(find.byType(VisitorHomeScreen)));
      expect(headline.style!.fontSize, theme.textTheme.displayLarge!.fontSize,
          reason: 'taille tirée du thème');
      expect(headline.style!.color, theme.colorScheme.onPrimary);
      expect(find.text('CampusConnect'),
          findsNWidgets(2)); // wordmark en haut, nom en grand en bas
      expect(find.widgetWithText(FilledButton, 'Créer un compte étudiant'),
          findsNWidgets(2));
      expect(find.text('Se connecter'), findsOneWidget);
      expect(find.text('Déjà inscrit ? Se connecter'), findsOneWidget);
      expect(
          find
              .byType(Icon)
              .evaluate()
              .where((e) => (e.widget as Icon).icon == Icons.home_rounded),
          isEmpty);
    });

    testWidgets('loads every feed once on open', (tester) async {
      await pump(tester);
      verify(() => articles.load()).called(1);
      verify(() => annonces.load()).called(1);
      verify(() => events.load()).called(1);
      verify(() => jobs.load()).called(1);
    });

    testWidgets('the primary action opens sign-up and the link opens login',
        (tester) async {
      await pump(tester);

      await tester.tap(
          find.widgetWithText(FilledButton, 'Créer un compte étudiant').first);
      await tester.pumpAndSettle();
      expect(find.byType(RegisterScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Retour'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Se connecter'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  group('house rules', () {
    testWidgets(
        'no gradient, no shadow, no hairline box, no "Voir tout", no tracked caps',
        (tester) async {
      stub(
          a: [_article, _gift],
          n: [_notice, _notice2],
          e: [_event],
          j: [_offer]);
      await pump(tester);

      // Le héro porte le dégradé diagonal demandé et ses deux cercles ; rien d'autre.
      final heroGradient = tester
          .widgetList<DecoratedBox>(find.byWidgetPredicate((w) =>
              w is DecoratedBox &&
              (w.decoration as BoxDecoration).gradient != null))
          .single
          .decoration as BoxDecoration;
      expect(gradients, findsNothing,
          reason: 'pas de Container dégradé ailleurs');
      expect(heroGradient.gradient, AppColors.visitorHeroGradient);
      // Les deux cercles translucides (0,08) du héro ; l'avatar d'initiale n'en fait pas partie.
      expect(find.byWidgetPredicate((w) {
        if (w is! Container || w.decoration is! BoxDecoration) return false;
        final d = w.decoration as BoxDecoration;
        return d.shape == BoxShape.circle &&
            d.color != null &&
            (d.color!.a - 0.08).abs() < 0.01;
      }), findsNWidgets(2));
      // Seules les quatre cartes de chiffres portent l'ombre demandée (16 / y4 / noir 5 %).
      final shadowed = tester.widgetList<Container>(shadows).toList();
      expect(shadowed, isEmpty,
          reason: 'aucun Container ombré en dehors des cartes de chiffres');
      final statCards = tester
          .widgetList<DecoratedBox>(find.byWidgetPredicate((w) =>
              w is DecoratedBox &&
              (w.decoration as BoxDecoration).boxShadow != null))
          .toList();
      expect(statCards, hasLength(4));
      for (final c in statCards) {
        expect((c.decoration as BoxDecoration).boxShadow, [kStatCardShadow]);
        expect((c.decoration as BoxDecoration).borderRadius,
            BorderRadius.circular(kStatCardRadius));
      }
      expect(hairlines, findsNothing);
      expect(find.text('Voir tout'), findsNothing);
      expect(find.textContaining('ÉPINGLÉ'), findsNothing);
      expect(find.textContaining('OFFICIELLE'), findsNothing);
      final horizontal = tester
          .widgetList<ListView>(find.byType(ListView))
          .where((l) => l.scrollDirection == Axis.horizontal);
      expect(horizontal, isEmpty,
          reason: 'plus de carrousels horizontaux identiques');
      for (final c in tester.widgetList<Card>(find.byType(Card))) {
        expect(c.elevation ?? 0, 0, reason: 'cartes tonales, sans ombre');
      }

      // Rien sous 13 px.
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        final size = t.style?.fontSize;
        if (size != null) {
          expect(size, greaterThanOrEqualTo(13),
              reason: '"${t.data}" est à $size px');
        }
      }
    });

    testWidgets(
        'the closing field is a flat brand colour and the hero is clipped at 32 at the bottom',
        (tester) async {
      await pump(tester);
      final fields = tester
          .widgetList<Material>(find.byType(Material))
          .map((m) => m.color)
          .whereType<Color>()
          .toList();
      expect(fields, contains(AppColors.authField));
      final clip = tester
          .widgetList<ClipRRect>(find.byType(ClipRRect))
          .firstWhere((c) =>
              c.borderRadius ==
              const BorderRadius.vertical(bottom: Radius.circular(32)));
      expect(clip, isNotNull);
    });

    testWidgets(
        'every section and the hero share the single horizontal margin constant',
        (tester) async {
      stub(a: [_article], n: [_notice], e: [_event], j: [_offer]);
      await pump(tester);
      expect(kPagePadding, 20);
      for (final label in [
        'Le campus,\nen direct.',
        'En ce moment',
        'Prochains événements',
        'À vendre ou à donner',
        'Annonces',
        'Stages et emplois',
        'Réservé aux étudiants d\'ESPRIT, avec leur email académique.'
      ]) {
        await tester.ensureVisible(find.text(label));
        expect(tester.getTopLeft(find.text(label)).dx, kPagePadding,
            reason: label);
      }
    });

    testWidgets(
        'the gap between "En ce moment" and the stat grid is exactly kHeaderGap',
        (tester) async {
      stub(a: [_article], n: [_notice], e: [_event], j: [_offer]);
      await pump(tester);
      final titleBottom = tester.getBottomLeft(find.text('En ce moment')).dy;
      final firstCardTop = tester.getTopLeft(find.byKey(const Key('pulse'))).dy;
      expect(firstCardTop - titleBottom, kHeaderGap);
    });

    testWidgets(
        'stat cards: 44 px tinted icon square, count over label, tappable',
        (tester) async {
      stub(a: [_article], n: [_notice], e: [_event], j: [_offer]);
      await pump(tester);
      final square = find.byWidgetPredicate((w) =>
          w is Container &&
          w.constraints?.maxWidth == 44 &&
          w.constraints?.maxHeight == 44 &&
          (w.decoration as BoxDecoration?)?.color ==
              ModuleColors.tint(ModuleColors.events));
      expect(square, findsOneWidget);
      final count = tester.widget<Text>(find.text('1').first);
      expect(count.style!.fontSize, 24);
      expect(count.style!.fontWeight, FontWeight.w700);
      final label = tester.widget<Text>(find.text('événements à venir'));
      expect(label.style!.fontSize, 13);
      expect(label.maxLines, 2);

      await tester.tap(find.text('événements à venir'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets(
        '"Se connecter" is a 36 dp outlined pill with a 48 dp tap target; subtitle is capped at 300',
        (tester) async {
      await pump(tester);
      final button = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Se connecter'));
      final style = button.style!;
      expect(style.fixedSize!.resolve({})!.height, 36);
      final side = style.side!.resolve({})!;
      expect(side.width, 1);
      expect(
          side.color,
          Theme.of(tester.element(find.byType(VisitorHomeScreen)))
              .colorScheme
              .onPrimary);
      expect(
          tester
              .getSize(find.widgetWithText(OutlinedButton, 'Se connecter'))
              .height,
          greaterThanOrEqualTo(48));
      final subtitle = find.text(
          'Annonces, événements, petites annonces et stages, entre étudiants d\'ESPRIT.');
      expect(tester.getSize(subtitle).width, lessThanOrEqualTo(300));
    });

    testWidgets(
        'touch targets are at least 48 dp and spacing follows the 8 dp grid',
        (tester) async {
      stub(a: [_article], n: [_notice], e: [_event], j: [_offer]);
      await pump(tester);
      for (final f in [
        find.text('Se connecter'),
        find.text('Tout voir').first,
        find.text('Déjà inscrit ? Se connecter')
      ]) {
        await tester.ensureVisible(f);
        final button = find
            .ancestor(
                of: f,
                matching: find.byWidgetPredicate((w) => w is ButtonStyleButton))
            .first;
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48),
            reason: 'cible tactile de $f');
      }
      for (final p in tester.widgetList<Padding>(find.byType(Padding))) {
        final e = p.padding;
        if (e is EdgeInsets) {
          for (final v in [e.left, e.right]) {
            if (v == 14) {
              continue; // padding des cartes de chiffres, demandé à 14
            }
            expect(v % 4, 0, reason: 'marge horizontale $v hors grille 4/8 dp');
          }
        }
      }
    });

    testWidgets('"Tout voir" leads to the login screen', (tester) async {
      stub(e: [_event]);
      await pump(tester);
      await tester.ensureVisible(find.text('Tout voir').first);
      await tester.tap(find.text('Tout voir').first);
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  group('content', () {
    testWidgets(
        'states the real numbers of the moment as four tiles, announced as one sentence',
        (tester) async {
      stub(a: [_article, _gift], n: [_notice], e: [_event], j: [_offer]);
      await pump(tester);

      expect(find.text('En ce moment'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('objets à vendre ou à donner'), findsOneWidget);
      expect(find.text('événements à venir'), findsOneWidget);
      final semantics =
          tester.widget<Semantics>(find.byKey(const Key('pulse')));
      expect(semantics.properties.label,
          'En ce moment : 1 événements à venir, 1 annonces, 2 objets à vendre ou à donner, 1 offres de stage ou d\'emploi');
    });

    testWidgets(
        'events are a dated list, articles a priced mosaic, notices a statement, offers an index',
        (tester) async {
      stub(
          a: [_article, _gift],
          n: [_notice2, _notice],
          e: [_event],
          j: [_offer]);
      await pump(tester);

      expect(find.text('7'), findsOneWidget);
      expect(find.text('nov.'), findsOneWidget);
      expect(find.text('Hackathon IA'), findsOneWidget);
      expect(find.text('Amphi B · Club IEEE'), findsOneWidget);

      expect(find.text('120 DT'), findsOneWidget);
      expect(find.text('Gratuit'), findsOneWidget);
      expect(find.byType(GridView),
          findsNothing); // mosaïque en rangées : hauteur libre, pas de ratio

      // L'annonce officielle épinglée passe en tête, en énoncé.
      final lead =
          tester.widget<Text>(find.text('Fermeture de la bibliothèque le 12'));
      final theme = Theme.of(tester.element(find.byType(VisitorHomeScreen)));
      expect(lead.style!.fontSize, theme.textTheme.headlineMedium!.fontSize);
      expect(find.widgetWithText(Chip, 'Officielle'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'Épinglée'), findsOneWidget);
      expect(find.text('Scolarité'), findsOneWidget);
      expect(find.text('Clés perdues près du parking'), findsOneWidget);

      expect(find.text('Stage développeur Flutter'), findsOneWidget);
      expect(find.text('Vermeg · Lac 2'), findsOneWidget);
      expect(find.widgetWithText(Chip, 'Stage'), findsOneWidget);
      expect(find.text('V'), findsOneWidget); // initiale de l'entreprise
    });

    testWidgets('an empty campus says so instead of showing grey boxes',
        (tester) async {
      await pump(tester);

      expect(find.text('Le campus démarre. Sois parmi les premiers à publier.'),
          findsOneWidget);
      expect(find.text('Aucun événement annoncé pour l\'instant.'),
          findsOneWidget);
      expect(find.text('Aucun objet proposé pour l\'instant.'), findsOneWidget);
      expect(
          find.text('Aucune annonce publiée pour l\'instant.'), findsOneWidget);
      expect(
          find.text('Aucune offre publiée pour l\'instant.'), findsOneWidget);
    });

    testWidgets('while feeds load with nothing cached, it says it is loading',
        (tester) async {
      stub(loading: true);
      await pump(tester);
      expect(find.text('Chargement du campus…'), findsOneWidget);
    });
  });

  group('acceptance', () {
    Future<void> pumpNarrow(WidgetTester tester,
        {double textScale = 1.0}) async {
      tester.view.physicalSize = const Size(360, 800);
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
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: const VisitorHomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('no overflow at 360 px wide', (tester) async {
      stub(
          a: [_article, _gift],
          n: [_notice, _notice2],
          e: [_event],
          j: [_offer]);
      await pumpNarrow(tester);
      await tester.ensureVisible(find.text('Déjà inscrit ? Se connecter'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow at 360 px wide with text scale 1.3',
        (tester) async {
      stub(
          a: [_article, _gift],
          n: [_notice, _notice2],
          e: [_event],
          j: [_offer]);
      await pumpNarrow(tester, textScale: 1.3);
      await tester.ensureVisible(find.text('Déjà inscrit ? Se connecter'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'nothing sits closer than 20 px to either edge, except the hero background',
        (tester) async {
      stub(
          a: [_article, _gift],
          n: [_notice, _notice2],
          e: [_event],
          j: [_offer]);
      await pumpNarrow(tester);
      for (final e in find.byType(Text).evaluate()) {
        final box = e.renderObject as RenderBox;
        // Rect tel que peint (tient compte des FittedBox qui réduisent le texte).
        final r = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
        final data = (e.widget as Text).data;
        expect(r.left, greaterThanOrEqualTo(kPagePadding - 0.01),
            reason: '"$data" à gauche');
        expect(r.right, lessThanOrEqualTo(360 - kPagePadding + 0.01),
            reason: '"$data" à droite');
      }
    });

    testWidgets(
        'sections are separated by kSectionGap and titles sit kHeaderGap above their content',
        (tester) async {
      stub(e: [_event]);
      await pumpNarrow(tester);
      expect(kSectionGap, 32);
      final title = find.text('Prochains événements');
      await tester.ensureVisible(title);
      final card = find
          .ancestor(of: find.text('Hackathon IA'), matching: find.byType(Card))
          .first;
      expect(tester.getTopLeft(card).dy - tester.getBottomLeft(title).dy,
          closeTo(kHeaderGap, 0.5));
    });
  });
}
