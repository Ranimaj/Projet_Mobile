import 'package:campusconnect/core/theme/app_theme.dart';
import 'package:campusconnect/main.dart';
import 'package:campusconnect/providers/annonce_provider.dart';
import 'package:campusconnect/providers/article_provider.dart';
import 'package:campusconnect/providers/event_provider.dart';
import 'package:campusconnect/providers/job_provider.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/screens/auth/register_screen.dart';
import 'package:campusconnect/screens/onboarding/onboarding_screen.dart';
import 'package:campusconnect/screens/visitor/visitor_home_screen.dart';
import 'package:campusconnect/services/app_prefs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/mocks.dart';

class _MockAuth extends Mock implements AuthProvider {}

class _MockArticles extends Mock implements ArticleProvider {}

class _MockAnnonces extends Mock implements AnnonceProvider {}

class _MockEvents extends Mock implements EventProvider {}

class _MockJobs extends Mock implements JobProvider {}

void main() {
  Future<void> pumpRouter(WidgetTester t, Map<String, Object> initial,
      {String? disabledMessage, AuthProvider? realAuth}) async {
    SharedPreferences.setMockInitialValues(initial);
    final prefs = await AppPrefs.load();
    final mockAuth = _MockAuth();
    final AuthProvider auth = realAuth ?? mockAuth;
    when(() => mockAuth.status).thenReturn(AuthStatus.visitor);
    when(() => mockAuth.isLoading).thenReturn(false);
    when(() => mockAuth.errorMessage).thenReturn(disabledMessage);
    when(() => mockAuth.errorCode)
        .thenReturn(disabledMessage == null ? null : AuthProvider.accountDisabledCode);
    when(() => mockAuth.clearError()).thenReturn(null);
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

  testWidgets('a disabled account is explained once on the visitor home', (t) async {
    await pumpRouter(t, {'onboarding_seen': true},
        disabledMessage: "Compte désactivé. Contacte l'administration.");
    await t.pump();
    expect(find.byType(VisitorHomeScreen), findsOneWidget);
    expect(find.text("Compte désactivé. Contacte l'administration."), findsOneWidget);
  });

  testWidgets('rebuilds while the error is still set schedule one snack', (t) async {
    // The mocked clearError leaves the error in place, like a rebuild that
    // lands before the post-frame clear.
    await pumpRouter(t, {'onboarding_seen': true},
        disabledMessage: "Compte désactivé. Contacte l'administration.");
    for (var i = 0; i < 2; i++) {
      t.element(find.byType(RootRouter)).markNeedsBuild();
      await t.pump();
    }
    expect(find.byType(SnackBar), findsOneWidget);
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(seconds: 1));
    }
    await t.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('rebuilds before and after the clear show a single snack (real clearError)',
      (t) async {
    final service = MockAuthService();
    when(() => service.authStateChanges).thenAnswer((_) => const Stream.empty());
    final auth = AuthProvider(authService: service);
    addTearDown(auth.dispose);
    await auth.continueAsVisitor();
    auth
      ..errorCode = AuthProvider.accountDisabledCode
      ..errorMessage = "Compte désactivé. Contacte l'administration.";

    await pumpRouter(t, {'onboarding_seen': true}, realAuth: auth);
    // Two more rebuilds of the router.
    await auth.continueAsVisitor();
    await t.pump();
    await auth.continueAsVisitor();
    await t.pump();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(auth.errorCode, isNull);
    // No second snack queued behind the first one.
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(seconds: 1));
    }
    await t.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);

    // A later disable is announced again.
    auth
      ..errorCode = AuthProvider.accountDisabledCode
      ..errorMessage = "Compte désactivé. Contacte l'administration.";
    await auth.continueAsVisitor();
    await t.pump();
    await t.pump();
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('popping the auth screen after onboarding shows the visitor home',
      (t) async {
    await pumpRouter(t, {});
    await t.tap(find.text('Commencer'));
    await t.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);

    Navigator.of(t.element(find.byType(RegisterScreen))).pop();
    await t.pumpAndSettle();
    expect(find.byType(VisitorHomeScreen), findsOneWidget);
    expect(find.byType(OnboardingScreen), findsNothing);
  });
}
