import 'package:campusconnect/core/theme/app_theme.dart';
import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/providers/admin_users_provider.dart';
import 'package:campusconnect/screens/admin/admin_card_review_screen.dart';
import 'package:campusconnect/screens/admin/admin_users_screen.dart';
import 'package:campusconnect/core/utils/auth_failure.dart';
import 'package:campusconnect/services/admin_user_service.dart';
import 'package:campusconnect/services/local_store.dart';
import 'package:campusconnect/widgets/pill_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../helpers/mocks.dart';
import '../helpers/pump_themed.dart';
import 'admin_memory_store.dart';

Future<void> _seed(LocalStore db, {bool secondAdmin = false}) async {
  Future<void> add(String id, String name, String role, int day,
      {Map<String, dynamic>? card, bool disabled = false}) {
    return db.set('users', id, {
      'fullName': name,
      'email': '$id@esprit.tn',
      'role': role,
      'disabled': disabled,
      'createdAt': DateTime(2026, 1, day),
      if (card != null) 'studentCard': card,
    });
  }

  await add('a1', 'Admin Un', 'admin', 1);
  if (secondAdmin) await add('a2', 'Admin Deux', 'admin', 2);
  await add('s1', 'Amel Ben Salah', 'student', 3, card: {
    'status': 'pending',
    'imagePath': '/app/student_cards/s1/card.jpg',
    'submittedAt': DateTime(2026, 10, 20),
  });
  await add('r1', 'Rim Recruteur', 'recruiter', 4, disabled: true);
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  late LocalStore db;
  late MockAuthService auth;
  late AdminUsersProvider provider;

  Map<String, dynamic> user(String id) => db.get('users', id)!;

  setUp(() => auth = MockAuthService());

  Future<void> pumpScreen(WidgetTester t,
      {Brightness brightness = Brightness.light,
      bool secondAdmin = false,
      StudentCardStatus? initialCardFilter}) async {
    db = MemoryLocalStore();
    await _seed(db, secondAdmin: secondAdmin);
    provider = AdminUsersProvider(AdminUserService(store: db, auth: auth), currentAdminUid: 'a1');
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
        home: AdminUsersScreen(initialCardFilter: initialCardFilter),
      ),
    ));
    await t.pump(const Duration(milliseconds: 50));
    await t.pump(const Duration(milliseconds: 50));
  }

  testWidgets('lists users with role and card chips', (t) async {
    await pumpScreen(t);
    expect(find.text('Utilisateurs'), findsOneWidget);
    expect(find.text('Amel Ben Salah'), findsOneWidget);
    expect(find.text('Admin Un'), findsOneWidget);
    expect(find.text('Rim Recruteur'), findsOneWidget);
    expect(find.text('Désactivé'), findsOneWidget);
    expect(find.text('En attente'), findsNWidgets(2)); // filter chip + card chip
  });

  testWidgets('role and pending filters narrow the list', (t) async {
    await pumpScreen(t);
    await t.tap(find.text('Recruteurs'));
    await t.pump();
    expect(find.text('Rim Recruteur'), findsOneWidget);
    expect(find.text('Amel Ben Salah'), findsNothing);
    await t.tap(find.text('Recruteurs'));
    await t.pump();
    await t.ensureVisible(find.text('En attente').first);
    await t.tap(find.text('En attente').first);
    await t.pump();
    expect(find.text('Amel Ben Salah'), findsOneWidget);
    expect(find.text('Admin Un'), findsNothing);
  });

  testWidgets('initialCardFilter pre-selects pending cards', (t) async {
    await pumpScreen(t, initialCardFilter: StudentCardStatus.pending);
    await t.pump();
    expect(provider.cardFilter, StudentCardStatus.pending);
    expect(find.text('Admin Un'), findsNothing);
    expect(find.text('Amel Ben Salah'), findsOneWidget);
  });

  testWidgets('typing in the search field filters after the debounce', (t) async {
    await pumpScreen(t);
    await t.enterText(find.byType(TextField), 'rim');
    await t.pump(const Duration(milliseconds: 450));
    expect(find.text('Rim Recruteur'), findsOneWidget);
    expect(find.text('Amel Ben Salah'), findsNothing);
  });

  testWidgets('empty result shows the empty state', (t) async {
    await pumpScreen(t);
    await t.enterText(find.byType(TextField), 'zzz');
    await t.pump(const Duration(milliseconds: 450));
    expect(find.text('Aucun utilisateur'), findsOneWidget);
  });

  testWidgets('sheet changes a role and writes it', (t) async {
    await pumpScreen(t);
    await t.tap(find.text('Amel Ben Salah'));
    await t.pumpAndSettle();
    expect(find.text('Changer le rôle'), findsOneWidget);
    await t.tap(find.text('Recruteur').last);
    await t.pump();
    await t.tap(find.widgetWithText(PillButton, 'Confirmer'));
    await t.pumpAndSettle();
    expect(user('s1')['role'], 'recruiter');
  });

  testWidgets('confirm is disabled when the last admin picks another role', (t) async {
    await pumpScreen(t);
    await t.tap(find.text('Admin Un'));
    await t.pumpAndSettle();
    await t.tap(find.text('Étudiant').last);
    await t.pump();
    final confirm = t.widget<PillButton>(find.widgetWithText(PillButton, 'Confirmer'));
    expect(confirm.onPressed, isNull);
  });

  testWidgets('another admin can be demoted when two exist', (t) async {
    await pumpScreen(t, secondAdmin: true);
    await t.tap(find.text('Admin Un'));
    await t.pumpAndSettle();
    await t.tap(find.text('Étudiant').last);
    await t.pump();
    final confirm = t.widget<PillButton>(find.widgetWithText(PillButton, 'Confirmer'));
    expect(confirm.onPressed, isNotNull);
  });

  testWidgets('disabling asks for confirmation: cancel writes nothing', (t) async {
    await pumpScreen(t);
    await t.tap(find.text('Amel Ben Salah'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(PillButton, 'Désactiver le compte'));
    await t.pumpAndSettle();
    expect(find.text('Désactiver ce compte ?'), findsOneWidget);
    await t.tap(find.text('Annuler'));
    await t.pumpAndSettle();
    expect(user('s1')['disabled'], false);
  });

  testWidgets('sheet disables (after confirm) then re-enables an account', (t) async {
    await pumpScreen(t);
    await t.tap(find.text('Amel Ben Salah'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(PillButton, 'Désactiver le compte'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(TextButton, 'Désactiver'));
    await t.pumpAndSettle();
    expect(user('s1')['disabled'], true);

    await t.tap(find.text('Rim Recruteur'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(PillButton, 'Réactiver le compte'), findsOneWidget);
    await t.tap(find.widgetWithText(PillButton, 'Réactiver le compte'));
    await t.pumpAndSettle();
    expect(user('r1')['disabled'], false);
  });

  testWidgets('the last enabled admin has no disable button on their own row', (t) async {
    await pumpScreen(t);
    await t.tap(find.text('Admin Un'));
    await t.pumpAndSettle();
    expect(find.text('Désactiver le compte'), findsNothing);
  });

  testWidgets('"Voir la carte" opens the review for a pending card only', (t) async {
    await pumpScreen(t);
    await t.tap(find.text('Rim Recruteur'));
    await t.pumpAndSettle();
    expect(find.text('Voir la carte'), findsNothing);
    Navigator.of(t.element(find.text('Changer le rôle'))).pop();
    await t.pumpAndSettle();

    await t.tap(find.text('Amel Ben Salah'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(PillButton, 'Voir la carte'));
    await t.pumpAndSettle();
    expect(find.byType(AdminCardReviewScreen), findsOneWidget);
    expect(find.text('Valider'), findsOneWidget);
  });

  group('Réinitialiser le mot de passe', () {
    Future<void> openReset(WidgetTester t) async {
      await pumpScreen(t);
      await t.tap(find.text('Amel Ben Salah'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.widgetWithText(PillButton, 'Réinitialiser le mot de passe'));
      await t.tap(find.widgetWithText(PillButton, 'Réinitialiser le mot de passe'));
      await t.pumpAndSettle();
      expect(find.text('Réinitialiser le mot de passe ?'), findsOneWidget);
    }

    testWidgets('cancel resets nothing', (t) async {
      await openReset(t);
      await t.tap(find.text('Annuler'));
      await t.pumpAndSettle();
      verifyNever(() => auth.resetPasswordByAdmin(any()));
    });

    testWidgets('confirm shows the temporary password, which can be copied', (t) async {
      when(() => auth.resetPasswordByAdmin('s1')).thenAnswer((_) async => 'Campus-abcdef42');
      String? copied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() =>
          t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await openReset(t);
      await t.tap(find.widgetWithText(TextButton, 'Réinitialiser'));
      await t.pumpAndSettle();

      verify(() => auth.resetPasswordByAdmin('s1')).called(1);
      expect(find.text('Mot de passe temporaire'), findsOneWidget);
      expect(find.text('Campus-abcdef42'), findsOneWidget);
      expectNoSmallText(t);

      await t.tap(find.text('Copier'));
      await t.pumpAndSettle();
      expect(copied, 'Campus-abcdef42');
      expect(find.text('Mot de passe copié'), findsOneWidget);

      await t.tap(find.text('Fermer'));
      await t.pumpAndSettle();
      expect(find.text('Mot de passe temporaire'), findsNothing);
    });

    testWidgets('a failure shows an error and no password', (t) async {
      when(() => auth.resetPasswordByAdmin('s1'))
          .thenThrow(AuthFailure.fromCode('user-not-found'));
      await openReset(t);
      await t.tap(find.widgetWithText(TextButton, 'Réinitialiser'));
      await t.pumpAndSettle();
      expect(find.text('Mot de passe temporaire'), findsNothing);
      expect(find.text('Réinitialisation impossible pour ce compte.'), findsOneWidget);
    });
  });

  for (final brightness in Brightness.values) {
    testWidgets('a11y checks (${brightness.name})', (t) async {
      await pumpScreen(t, brightness: brightness);
      expectNoSmallText(t);
      expectTapTargets(t);
      await t.tap(find.text('Amel Ben Salah'));
      await t.pumpAndSettle();
      expectNoSmallText(t);
      // expectTapTargets would flag the Material Radio's inner 40 dp detector;
      // each role row is a full-width ListTile, asserted directly instead.
      for (final row in find.byType(RadioListTile<UserRole>).evaluate()) {
        expect((row.renderObject! as RenderBox).size.height, greaterThanOrEqualTo(48));
      }
    });
  }
}
