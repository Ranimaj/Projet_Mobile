import 'package:campusconnect/screens/profile/assistant_screen.dart';
import 'package:campusconnect/screens/profile/student_card_screen.dart';
import 'package:campusconnect/services/ai/user_assistant.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/authenticated.dart';

void main() {
  late AuthHarness h;
  setUp(() => h = AuthHarness());
  tearDown(() => h.dispose());

  testWidgets('greets the user and shows profile progress', (tester) async {
    await h.signIn(tester);
    await h.pump(tester, const AssistantScreen(assistant: LocalUserAssistant()));

    expect(find.textContaining('Salut Amel'), findsOneWidget);
    expect(find.text('Profil complet à 33 %'), findsOneWidget);
  });

  testWidgets('a suggestion gets an answer with a working action button', (tester) async {
    await h.signIn(tester);
    await h.pump(tester, const AssistantScreen(assistant: LocalUserAssistant()));

    await tester.ensureVisible(find.text('Où en est ma carte étudiant ?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Où en est ma carte étudiant ?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('pas encore envoyé ta carte'), findsOneWidget);

    await tester.tap(find.byKey(const Key('assistant-action-studentCard')).last);
    await tester.pumpAndSettle();
    expect(find.byType(StudentCardScreen), findsOneWidget);
  });

  testWidgets('typed question is sent; profile-only actions use the callback', (tester) async {
    AssistantAction? called;
    await h.signIn(tester);
    await h.pump(tester, AssistantScreen(assistant: const LocalUserAssistant(), onProfileAction: (a) => called = a));

    await tester.enterText(find.byKey(const Key('assistant-input')), 'Vérifier mon numéro de téléphone');
    await tester.tap(find.byKey(const Key('assistant-send')));
    await tester.pumpAndSettle();

    expect(find.text('Vérifier mon numéro de téléphone'), findsOneWidget);
    await tester.tap(find.byKey(const Key('assistant-action-verifyPhone')));
    expect(called, AssistantAction.verifyPhone);
  });

  testWidgets('without the callback, profile-only actions are hidden', (tester) async {
    await h.signIn(tester);
    await h.pump(tester, const AssistantScreen(assistant: LocalUserAssistant()));

    await tester.enterText(find.byKey(const Key('assistant-input')), 'téléphone');
    await tester.tap(find.byKey(const Key('assistant-send')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('assistant-action-verifyPhone')), findsNothing);
  });
}
