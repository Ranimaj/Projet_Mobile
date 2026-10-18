import 'package:campusconnect/core/utils/auth_failure.dart';
import 'package:campusconnect/screens/profile/change_password_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/authenticated.dart';
import '../helpers/pump_app.dart';

void main() {
  late AuthHarness h;

  setUp(() => h = AuthHarness());
  tearDown(() => h.dispose());

  Future<void> open(WidgetTester tester) async {
    await h.signIn(tester);
    await h.pump(tester, const ChangePasswordScreen());
  }

  testWidgets('requires every field', (tester) async {
    await open(tester);

    await tapText(tester, 'Mettre à jour');
    await tester.pump();

    expect(find.text('Mot de passe requis'), findsNWidgets(2));
    expect(find.text('Confirmation requise'), findsOneWidget);
    verifyNever(() => h.service.changePassword(
          currentPassword: any(named: 'currentPassword'),
          newPassword: any(named: 'newPassword'),
        ));
  });

  testWidgets('enforces strength, difference from current and confirmation', (tester) async {
    await open(tester);

    await enterField(tester, 0, 'secret123');
    await enterField(tester, 1, 'secret123');
    await enterField(tester, 2, 'other');
    await tapText(tester, 'Mettre à jour');
    await tester.pump();
    expect(find.text('Identique au mot de passe actuel'), findsOneWidget);
    expect(find.text('Les mots de passe ne correspondent pas'), findsOneWidget);

    await enterField(tester, 1, 'short1');
    await tapText(tester, 'Mettre à jour');
    await tester.pump();
    expect(find.text('8 caractères minimum'), findsOneWidget);
  });

  testWidgets('shows the strength meter while typing', (tester) async {
    await open(tester);

    await enterField(tester, 1, 'Nouveau456!');
    await tester.pump();

    expect(find.text('Robustesse : Excellent'), findsOneWidget);
  });

  testWidgets('updates the password and closes the screen', (tester) async {
    when(() => h.service.changePassword(
          currentPassword: any(named: 'currentPassword'),
          newPassword: any(named: 'newPassword'),
        )).thenAnswer((_) async {});
    await open(tester);

    await enterField(tester, 0, 'secret123');
    await enterField(tester, 1, 'nouveau456');
    await enterField(tester, 2, 'nouveau456');
    await tapText(tester, 'Mettre à jour');
    await tester.pumpAndSettle();

    verify(() => h.service.changePassword(currentPassword: 'secret123', newPassword: 'nouveau456'))
        .called(1);
    expect(find.byType(ChangePasswordScreen), findsNothing);
    expect(find.text('Mot de passe mis à jour.'), findsOneWidget);
  });

  testWidgets('a wrong current password keeps the screen open with the message', (tester) async {
    when(() => h.service.changePassword(
          currentPassword: any(named: 'currentPassword'),
          newPassword: any(named: 'newPassword'),
        )).thenThrow(AuthFailure.fromCode('wrong-password'));
    await open(tester);

    await enterField(tester, 0, 'bad');
    await enterField(tester, 1, 'nouveau456');
    await enterField(tester, 2, 'nouveau456');
    await tapText(tester, 'Mettre à jour');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Email ou mot de passe incorrect.'), findsOneWidget);
    expect(find.byType(ChangePasswordScreen), findsOneWidget);
  });
}
