import 'package:campusconnect/core/theme/app_theme.dart';
import 'package:campusconnect/main.dart';
import 'package:campusconnect/providers/annonce_provider.dart';
import 'package:campusconnect/providers/article_provider.dart';
import 'package:campusconnect/providers/event_provider.dart';
import 'package:campusconnect/providers/job_provider.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/screens/onboarding/onboarding_screen.dart';
import 'package:campusconnect/screens/visitor/visitor_home_screen.dart';
import 'package:campusconnect/services/app_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockAuth extends Mock implements AuthProvider {}

class _MockArticles extends Mock implements ArticleProvider {}

class _MockAnnonces extends Mock implements AnnonceProvider {}

class _MockEvents extends Mock implements EventProvider {}

class _MockJobs extends Mock implements JobProvider {}

void main() {
  Future<void> pumpRouter(WidgetTester t, Map<String, Object> initial) async {
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await AppPrefs.load();
    final auth = _MockAuth();
    when(() => auth.status).thenReturn(AuthStatus.visitor);
    final articles = _MockArticles();
    final annonces = _MockAnnonces();
    final events = _MockEvents();
    final jobs = _MockJobs();
    when(() => articles.items).thenReturn([]);
    when(() => articles.isLoading).thenReturn(false);
    when(() => articles.load()).thenAnswer((_) async {});
    when(() => annonces.items).thenReturn([]);
    when(() => annonces.publicPreview).thenReturn([]);
    when(() => annonces.isLoading).thenReturn(false);
    when(() => annonces.load()).thenAnswer((_) async {});
    when(() => events.upcoming).thenReturn([]);
    when(() => events.publicPreview).thenReturn([]);
    when(() => events.isLoading).thenReturn(false);
    when(() => events.load()).thenAnswer((_) async {});
    when(() => jobs.offers).thenReturn([]);
    when(() => jobs.isLoading).thenReturn(false);
    when(() => jobs.load()).thenAnswer((_) async {});
    t.view.physicalSize = const Size(420, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MultiProvider(
      providers: [
        Provider<AppPrefs>.value(value: prefs),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<ArticleProvider>.value(value: articles),
        ChangeNotifierProvider<AnnonceProvider>.value(value: annonces),
        ChangeNotifierProvider<EventProvider>.value(value: events),
        ChangeNotifierProvider<JobProvider>.value(value: jobs),
      ],
      child: MaterialApp(theme: AppTheme.light, home: const RootRouter()),
    ));
    await t.pump();
  }

  testWidgets('shows onboarding when it has not been seen', (t) async {
    await pumpRouter(t, {});
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.byType(VisitorHomeScreen), findsNothing);
  });

  testWidgets('shows the visitor home once onboarding was seen', (t) async {
    await pumpRouter(t, {'onboarding_seen': true});
    expect(find.byType(VisitorHomeScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
  });
}
