import 'package:campusconnect/core/theme/app_theme.dart';
import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/providers/admin_users_provider.dart';
import 'package:campusconnect/screens/admin/admin_card_review_screen.dart';
import 'package:campusconnect/services/admin_user_service.dart';
import 'package:campusconnect/services/local_store.dart';
import 'package:campusconnect/widgets/app_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import '../helpers/pump_themed.dart';
import 'admin_memory_store.dart';

void main() {
  late LocalStore db;
  late AdminUsersProvider provider;
  const cardPath = '/app/student_cards/s1/card.jpg';

  Map<String, dynamic> stored() => db.get('users', 's1')!;

  setUpAll(() => initializeDateFormatting('fr_FR'));

  AppUser student(StudentCardStatus status, {String? imagePath = cardPath}) => AppUser(
        id: 's1',
        fullName: 'Amel Ben Salah',
        email: 's1@esprit.tn',
        major: 'Génie Logiciel',
        year: '3ème année',
        studentId: '20ABC123',
        createdAt: DateTime(2026, 1, 1),
        studentCard: StudentCard(
          status: status,
          imagePath: imagePath,
          submittedAt: DateTime(2026, 10, 20),
          reviewedAt: status == StudentCardStatus.verified ? DateTime(2026, 10, 25) : null,
        ),
      );

  Future<void> pumpReview(WidgetTester t, AppUser user,
      {Brightness brightness = Brightness.light}) async {
    db = MemoryLocalStore();
    await db.set('users', 's1', {
      'fullName': user.fullName,
      'email': user.email,
      'role': 'student',
      'createdAt': user.createdAt,
      'studentCard': {
        'status': user.studentCard.status.name,
        if (user.studentCard.imagePath != null) 'imagePath': user.studentCard.imagePath,
        'submittedAt': DateTime(2026, 10, 20),
      },
    });
    provider = AdminUsersProvider(AdminUserService(store: db), currentAdminUid: 'a1');
    addTearDown(provider.dispose);
    t.view.physicalSize = const Size(420, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(ChangeNotifierProvider<AdminUsersProvider>.value(
      value: provider,
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => AdminCardReviewScreen(user: user))),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  testWidgets('shows identity rows and both actions for a pending card', (t) async {
    await pumpReview(t, student(StudentCardStatus.pending));
    expect(find.text('Amel Ben Salah'), findsOneWidget);
    expect(find.text('Génie Logiciel'), findsOneWidget);
    expect(find.text('3ème année'), findsOneWidget);
    expect(find.text('20ABC123'), findsOneWidget);
    expect(find.text('20 octobre 2026'), findsOneWidget);
    expect(find.text('Refuser'), findsOneWidget);
    expect(find.text('Valider'), findsOneWidget);
  });

  testWidgets('shows the stored local photo directly, zoomable', (t) async {
    await pumpReview(t, student(StudentCardStatus.pending));
    final image = t.widget<AppImage>(find.byType(AppImage));
    expect(image.url, cardPath);
    await t.tap(find.byType(AppImage));
    await t.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(t.widget<AppImage>(find.descendant(
            of: find.byType(InteractiveViewer), matching: find.byType(AppImage)))
        .url, cardPath);
    await t.tap(find.byTooltip('Fermer'));
    await t.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('a card without photo shows a placeholder', (t) async {
    await pumpReview(t, student(StudentCardStatus.pending, imagePath: null));
    expect(find.byType(AppImage), findsNothing);
    expect(find.text('Aucune image'), findsOneWidget);
  });

  testWidgets('approve writes verified, snacks and pops', (t) async {
    await pumpReview(t, student(StudentCardStatus.pending));
    await t.tap(find.text('Valider'));
    await t.pumpAndSettle();
    final data = stored();
    expect(data['isVerifiedStudent'], true);
    expect((data['studentCard'] as Map)['status'], 'verified');
    expect((data['studentCard'] as Map)['reviewedBy'], 'a1');
    expect(find.text('Carte validée'), findsOneWidget);
    expect(find.byType(AdminCardReviewScreen), findsNothing);
  });

  testWidgets('a card resubmitted meanwhile is not decided: snack and pop', (t) async {
    await pumpReview(t, student(StudentCardStatus.pending));
    await db.update('users', 's1', {
      'studentCard': {
        'status': 'pending',
        'imagePath': '/app/student_cards/s1/new.jpg',
        'submittedAt': DateTime(2026, 10, 27),
      },
    });
    await t.tap(find.text('Valider'));
    await t.pumpAndSettle();
    final data = stored();
    expect((data['studentCard'] as Map)['status'], 'pending');
    expect(data['isVerifiedStudent'], isNull);
    expect(find.text('La carte a changé, rouvre-la'), findsOneWidget);
    expect(find.byType(AdminCardReviewScreen), findsNothing);
  });

  testWidgets('reject requires a reason of at least 5 characters', (t) async {
    await pumpReview(t, student(StudentCardStatus.pending));
    await t.tap(find.text('Refuser'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField), 'abc');
    await t.tap(find.widgetWithText(TextButton, 'Refuser'));
    await t.pump();
    expect(find.text('Motif requis (5 caractères minimum)'), findsOneWidget);
    expect(stored()['isVerifiedStudent'], isNull);

    await t.enterText(find.byType(TextFormField), 'Photo floue');
    await t.tap(find.widgetWithText(TextButton, 'Refuser'));
    await t.pumpAndSettle();
    final data = stored();
    expect(data['isVerifiedStudent'], false);
    expect((data['studentCard'] as Map)['status'], 'rejected');
    expect((data['studentCard'] as Map)['rejectReason'], 'Photo floue');
    expect(find.text('Carte refusée'), findsOneWidget);
    expect(find.byType(AdminCardReviewScreen), findsNothing);
  });

  testWidgets('an already verified card hides the actions and shows the review date', (t) async {
    await pumpReview(t, student(StudentCardStatus.verified));
    expect(find.text('Valider'), findsNothing);
    expect(find.text('Refuser'), findsNothing);
    expect(find.text('Validée le 25 octobre 2026'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets('a11y checks (${brightness.name})', (t) async {
      await pumpReview(t, student(StudentCardStatus.pending), brightness: brightness);
      expectNoSmallText(t);
      expectTapTargets(t);
    });
  }
}
