import 'package:campusconnect/core/theme/app_theme.dart';
import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/providers/admin_users_provider.dart';
import 'package:campusconnect/screens/admin/admin_card_review_screen.dart';
import 'package:campusconnect/services/admin_user_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../helpers/mocks.dart';
import '../helpers/pump_themed.dart';

void main() {
  late FakeFirebaseFirestore db;
  late AdminUsersProvider provider;

  setUpAll(() => initializeDateFormatting('fr_FR'));

  AppUser student(StudentCardStatus status) => AppUser(
        id: 's1',
        fullName: 'Amel Ben Salah',
        email: 's1@esprit.tn',
        major: 'Génie Logiciel',
        year: '3ème année',
        studentId: '20ABC123',
        createdAt: DateTime(2026, 1, 1),
        studentCard: StudentCard(
          status: status,
          imagePath: 'student_cards/s1/card.jpg',
          submittedAt: DateTime(2026, 10, 20),
          reviewedAt: status == StudentCardStatus.verified ? DateTime(2026, 10, 25) : null,
        ),
      );

  Future<void> pumpReview(WidgetTester t, AppUser user,
      {Brightness brightness = Brightness.light}) async {
    db = FakeFirebaseFirestore();
    final storage = MockStorageService();
    when(() => storage.downloadUrl(any())).thenAnswer((_) async => throw Exception('no net'));
    await db.collection('users').doc('s1').set({
      'fullName': user.fullName,
      'email': user.email,
      'role': 'student',
      'createdAt': Timestamp.fromDate(user.createdAt),
      'studentCard': {
        'status': user.studentCard.status.name,
        'imagePath': 'student_cards/s1/card.jpg',
        'submittedAt': Timestamp.fromDate(DateTime(2026, 10, 20)),
      },
    });
    provider = AdminUsersProvider(AdminUserService(db, storage: storage), currentAdminUid: 'a1');
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

  testWidgets('approve writes verified, snacks and pops', (t) async {
    await pumpReview(t, student(StudentCardStatus.pending));
    await t.tap(find.text('Valider'));
    await t.pumpAndSettle();
    final data = (await db.collection('users').doc('s1').get()).data()!;
    expect(data['isVerifiedStudent'], true);
    expect((data['studentCard'] as Map)['status'], 'verified');
    expect((data['studentCard'] as Map)['reviewedBy'], 'a1');
    expect(find.text('Carte validée'), findsOneWidget);
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
    expect((await db.collection('users').doc('s1').get()).data()!['isVerifiedStudent'], isNull);

    await t.enterText(find.byType(TextFormField), 'Photo floue');
    await t.tap(find.widgetWithText(TextButton, 'Refuser'));
    await t.pumpAndSettle();
    final data = (await db.collection('users').doc('s1').get()).data()!;
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
