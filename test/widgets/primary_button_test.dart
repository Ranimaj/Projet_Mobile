import 'package:campusconnect/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget button, {double width = 160}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: SizedBox(width: width, child: button)),
        ),
      ),
    );
  }

  testWidgets('a long label never overflows a narrow button', (tester) async {
    await pump(
      tester,
      PrimaryButton(label: 'Retour à la connexion et recommencer', icon: Icons.arrow_back, onPressed: () {}),
      width: 120,
    );
    // Aucun débordement : flutter_test transforme les overflows en exceptions.
    expect(tester.takeException(), isNull);
    expect(find.text('Retour à la connexion et recommencer'), findsOneWidget);
  });

  testWidgets('tapping calls onPressed once; loading and disabled states do not', (tester) async {
    var taps = 0;
    await pump(tester, PrimaryButton(label: 'Go', onPressed: () => taps++));
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(taps, 1);

    await pump(tester, PrimaryButton(label: 'Go', isLoading: true, onPressed: () => taps++));
    // Pas de pumpAndSettle : le spinner anime indéfiniment.
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Go'), findsNothing);
    await tester.tap(find.byType(CircularProgressIndicator));
    await tester.pump();
    expect(taps, 1);

    await pump(tester, const PrimaryButton(label: 'Go', onPressed: null));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Go'));
    expect(taps, 1);
  });

  testWidgets('is exposed as a button to assistive technologies', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, PrimaryButton(label: 'Se connecter', onPressed: () {}));

    expect(
      tester.getSemantics(find.text('Se connecter')),
      isSemantics(label: 'Se connecter', isButton: true, isEnabled: true, hasTapAction: true),
    );
    handle.dispose();
  });
}
