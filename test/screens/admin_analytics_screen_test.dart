import 'dart:async';

import 'package:campusconnect/core/theme/app_theme.dart';
import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/providers/admin_users_provider.dart';
import 'package:campusconnect/screens/admin/admin_analytics_screen.dart';
import 'package:campusconnect/services/admin_user_service.dart';
import 'package:campusconnect/widgets/charts/area_line_chart.dart';
import 'package:campusconnect/widgets/charts/donut_chart.dart';
import 'package:campusconnect/widgets/charts/h_bar_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../helpers/pump_themed.dart';

class _MockService extends Mock implements AdminUserService {}

void main() {
  final now = DateTime(2026, 10, 28, 12);

  AppUser u(String id, int daysAgo,
          {UserRole role = UserRole.student, StudentCardStatus card = StudentCardStatus.none}) =>
      AppUser(
        id: id,
        fullName: id,
        email: '$id@esprit.tn',
        role: role,
        createdAt: now.subtract(Duration(days: daysAgo)),
        studentCard: StudentCard(status: card),
      );

  // 3 sign-ups in the last 7 days, 1 in the 7 before (+200 %); 1 more only
  // inside the 30-day window.
  final users = [
    u('a', 0, role: UserRole.admin),
    u('b', 2, card: StudentCardStatus.pending),
    u('c', 5, card: StudentCardStatus.verified),
    u('d', 9),
    u('e', 20, role: UserRole.recruiter, card: StudentCardStatus.rejected),
  ];

  Future<void> pumpScreen(WidgetTester t, {Brightness brightness = Brightness.light}) async {
    final service = _MockService();
    final controller = StreamController<List<AppUser>>();
    addTearDown(controller.close);
    when(() => service.watchAll()).thenAnswer((_) => controller.stream);
    final provider = AdminUsersProvider(service, currentAdminUid: 'a');
    addTearDown(provider.dispose);
    controller.add(users);
    t.view.physicalSize = const Size(420, 2400);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(ChangeNotifierProvider<AdminUsersProvider>.value(
      value: provider,
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        home: AdminAnalyticsScreen(now: () => now),
      ),
    ));
    await t.pump(const Duration(milliseconds: 50));
    await t.pump(const Duration(milliseconds: 50));
  }

  testWidgets('renders the stat tiles and the three charts', (t) async {
    await pumpScreen(t);
    expect(find.text('Inscrits'), findsOneWidget);
    expect(find.text('Cartes en attente'), findsOneWidget);
    expect(find.text('Inscriptions par jour'), findsOneWidget);
    expect(find.text('Par rôle'), findsOneWidget);
    expect(find.text('Vérification des cartes'), findsOneWidget);
    expect(find.byType(AreaLineChart), findsOneWidget);
    expect(find.byType(DonutChart), findsOneWidget);
    expect(find.byType(HBarChart), findsOneWidget);
  });

  testWidgets('switching the period recomputes the sign-ups', (t) async {
    await pumpScreen(t);
    // default 30 days: all five users signed up in the window
    expect(find.text('5'), findsWidgets);
    await t.tap(find.text('7 j'));
    await t.pump();
    // last 7 days: a, b, c; previous 7 days: d -> +200 %
    expect(find.text('3'), findsWidgets);
    expect(find.textContaining('+ 200 %'), findsOneWidget);
    expect(t.widget<AreaLineChart>(find.byType(AreaLineChart)).points, hasLength(7));
    await t.tap(find.text('90 j'));
    await t.pump();
    expect(t.widget<AreaLineChart>(find.byType(AreaLineChart)).points, hasLength(90));
  });

  for (final brightness in Brightness.values) {
    testWidgets('a11y checks (${brightness.name})', (t) async {
      await pumpScreen(t, brightness: brightness);
      expectNoSmallText(t);
      expectTapTargets(t);
    });
  }
}
