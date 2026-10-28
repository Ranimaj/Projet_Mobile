import 'package:campusconnect/core/constants/layout.dart';
import 'package:campusconnect/core/theme/app_theme.dart';
import 'package:campusconnect/providers/annonce_provider.dart';
import 'package:campusconnect/providers/article_provider.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/providers/connectivity_provider.dart';
import 'package:campusconnect/providers/event_provider.dart';
import 'package:campusconnect/providers/job_provider.dart';
import 'package:campusconnect/screens/home/app_shell.dart';
import 'package:campusconnect/screens/home/home_screen.dart';
import 'package:campusconnect/widgets/floating_nav_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../helpers/authenticated.dart';

class _MockArticles extends Mock implements ArticleProvider {}

class _MockAnnonces extends Mock implements AnnonceProvider {}

class _MockEvents extends Mock implements EventProvider {}

class _MockJobs extends Mock implements JobProvider {}

void main() {
  late AuthHarness h;
  late _MockArticles articles;
  late _MockAnnonces annonces;
  late _MockEvents events;
  late _MockJobs jobs;

  setUpAll(() => initializeDateFormatting('fr'));

  setUp(() {
    h = AuthHarness();
    articles = _MockArticles();
    annonces = _MockAnnonces();
    events = _MockEvents();
    jobs = _MockJobs();
    when(() => articles.items).thenReturn(const []);
    when(() => articles.isLoading).thenReturn(false);
    when(() => articles.categoryFilter).thenReturn(null);
    when(() => articles.showOnlyFree).thenReturn(false);
    when(() => articles.load()).thenAnswer((_) async {});
    when(() => annonces.items).thenReturn(const []);
    when(() => annonces.isLoading).thenReturn(false);
    when(() => annonces.categoryFilter).thenReturn(null);
    when(() => annonces.load()).thenAnswer((_) async {});
    when(() => events.upcoming).thenReturn(const []);
    when(() => events.isLoading).thenReturn(false);
    when(() => events.categoryFilter).thenReturn(null);
    when(() => events.eventsOnDay(any())).thenReturn(const []);
    when(() => events.load()).thenAnswer((_) async {});
    when(() => jobs.offers).thenReturn(const []);
    when(() => jobs.myApplications).thenReturn(const []);
    when(() => jobs.isLoading).thenReturn(false);
    when(() => jobs.typeFilter).thenReturn(null);
    when(() => jobs.recommendedFor(any())).thenReturn(const []);
    when(() => jobs.load()).thenAnswer((_) async {});
    when(() => jobs.loadMyApplications(any())).thenAnswer((_) async {});
  });
  tearDown(() => h.dispose());

  Future<void> pumpShell(WidgetTester tester) async {
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
        child: MaterialApp(theme: AppTheme.light, home: const AppShell()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder inBar(String label) => find.descendant(
      of: find.byType(FloatingNavBar), matching: find.bySemanticsLabel(label));

  testWidgets(
      'shows the floating bar with five items and no BottomNavigationBar',
      (tester) async {
    await pumpShell(tester);
    expect(find.byType(BottomNavigationBar), findsNothing);
    expect(find.byType(FloatingNavBar), findsOneWidget);
    for (final label in [
      'Accueil',
      'Marché',
      'Annonces',
      'Événements',
      'Stages'
    ]) {
      expect(inBar(label), findsOneWidget, reason: label);
    }
    expect(inBar('Profil'), findsNothing);
  });

  testWidgets('tapping Annonces switches the IndexedStack to index 2',
      (tester) async {
    await pumpShell(tester);
    int index() =>
        tester.widget<IndexedStack>(find.byType(IndexedStack)).index!;
    expect(index(), 0);
    await tester.tap(inBar('Annonces'));
    await tester.pumpAndSettle();
    expect(index(), 2);
  });

  testWidgets('tab content clears the floating bar', (tester) async {
    await pumpShell(tester);
    final padding = tester.widget<Padding>(find
        .ancestor(of: find.byType(HomeScreen), matching: find.byType(Padding))
        .first);
    expect((padding.padding as EdgeInsets).bottom,
        greaterThanOrEqualTo(kFloatingNavInset));
  });

  testWidgets('tab padding adds the system bottom inset', (tester) async {
    await pumpShell(tester);
    final padding = tester.widget<Padding>(find
        .ancestor(of: find.byType(HomeScreen), matching: find.byType(Padding))
        .first);
    expect((padding.padding as EdgeInsets).bottom, kFloatingNavInset);

    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetViewPadding);
    await tester.pump();
    final padded = tester.widget<Padding>(find
        .ancestor(of: find.byType(HomeScreen), matching: find.byType(Padding))
        .first);
    expect((padded.padding as EdgeInsets).bottom, kFloatingNavInset + 34);
  });
}
