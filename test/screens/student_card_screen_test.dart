import 'dart:io';

import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/screens/profile/student_card_screen.dart';
import 'package:campusconnect/services/student_card_service.dart';
import 'package:campusconnect/widgets/pill_button.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/authenticated.dart';
import '../helpers/pump_themed.dart';

class MockCardService extends Mock implements StudentCardService {}

class MockPicker extends Mock implements ImagePicker {}

void main() {
  late MockCardService cards;
  late MockPicker picker;
  late AuthHarness h;

  setUpAll(() {
    registerFallbackValue(File('x'));
    registerFallbackValue(ImageSource.gallery);
  });

  setUp(() {
    cards = MockCardService();
    picker = MockPicker();
    h = AuthHarness(studentCardService: cards);
    when(() => cards.hasQueuedSubmission(any())).thenReturn(false);
    when(() => picker.pickImage(
          source: any(named: 'source'),
          imageQuality: any(named: 'imageQuality'),
          maxWidth: any(named: 'maxWidth'),
        )).thenAnswer((_) async => XFile('/tmp/card.jpg'));
  });

  tearDown(() => h.dispose());

  PillButton sendButton(WidgetTester tester) =>
      tester.widget<PillButton>(find.widgetWithText(PillButton, 'Envoyer pour validation'));

  testWidgets('send is disabled until a photo is picked', (tester) async {
    await h.signIn(tester);
    await h.pump(tester, StudentCardScreen(picker: picker));

    expect(find.text('Galerie'), findsOneWidget);
    expect(find.text('Appareil photo'), findsOneWidget);
    expect(sendButton(tester).onPressed, isNull);

    await tester.tap(find.text('Galerie'));
    await tester.pumpAndSettle();
    expect(sendButton(tester).onPressed, isNotNull);
  });

  testWidgets('pick, send online: submits, shows the snack and pops', (tester) async {
    when(() => cards.submit(
          uid: any(named: 'uid'),
          photo: any(named: 'photo'),
          isOnline: any(named: 'isOnline'),
          now: any(named: 'now'),
        )).thenAnswer((_) async => StudentCard.pending(
          imagePath: 'student_cards/uid-1/1.jpg',
          submittedAt: DateTime(2026, 1, 1),
        ));
    await h.signIn(tester);
    await h.pump(tester, StudentCardScreen(picker: picker));

    await tester.tap(find.text('Galerie'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Envoyer pour validation'));
    await tester.pumpAndSettle();

    final captured = verify(() => cards.submit(
          uid: 'uid-1',
          photo: captureAny(named: 'photo'),
          isOnline: true,
          now: any(named: 'now'),
        )).captured;
    expect((captured.single as File).path, '/tmp/card.jpg');
    expect(h.provider.currentUser!.studentCard.status, StudentCardStatus.pending);
    expect(find.text('Carte envoyée, en attente de validation'), findsOneWidget);
    expect(find.byType(StudentCardScreen), findsNothing);
  });

  testWidgets('offline send uses the queued wording', (tester) async {
    when(() => h.connectivity.isOnline).thenReturn(false);
    when(() => cards.submit(
          uid: any(named: 'uid'),
          photo: any(named: 'photo'),
          isOnline: false,
          now: any(named: 'now'),
        )).thenAnswer((_) async => const StudentCard(status: StudentCardStatus.pending));
    await h.signIn(tester);
    await h.pump(tester, StudentCardScreen(picker: picker));

    await tester.tap(find.text('Appareil photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Envoyer pour validation'));
    await tester.pumpAndSettle();

    expect(find.text('Carte enregistrée, envoi à la reconnexion'), findsOneWidget);
  });

  testWidgets('rejected card shows the chip, the reason and Renvoyer', (tester) async {
    await h.signIn(
      tester,
      user: sampleUser.copyWith(
        studentCard: const StudentCard(
            status: StudentCardStatus.rejected, rejectReason: 'Photo floue'),
      ),
    );
    await h.pump(tester, StudentCardScreen(picker: picker));

    expect(find.text('Carte refusée'), findsOneWidget);
    expect(find.text('Motif : Photo floue'), findsOneWidget);
    expect(find.text('Renvoyer'), findsOneWidget);
    expectNoSmallText(tester);
    expectTapTargets(tester);
  });

  testWidgets('pending card waiting for the network says so', (tester) async {
    when(() => cards.hasQueuedSubmission('uid-1')).thenReturn(true);
    await h.signIn(
      tester,
      user: sampleUser.copyWith(studentCard: const StudentCard(status: StudentCardStatus.pending)),
    );
    await h.pump(tester, StudentCardScreen(picker: picker));

    expect(find.text('En attente de connexion'), findsOneWidget);
  });

  testWidgets('pending card shows the in-review chip', (tester) async {
    await h.signIn(
      tester,
      user: sampleUser.copyWith(studentCard: const StudentCard(status: StudentCardStatus.pending)),
    );
    await h.pump(tester, StudentCardScreen(picker: picker));

    expect(find.text('En cours de validation'), findsOneWidget);
  });
}
