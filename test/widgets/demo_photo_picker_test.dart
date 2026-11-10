import 'package:campusconnect/core/theme/app_tokens.dart';
import 'package:campusconnect/services/demo_articles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sélecteur des photos de démonstration (Vente & Don) : aucune carte ne
/// déborde, la feuille défile et la dernière photo reste atteignable.
void main() {
  Future<void> open(WidgetTester tester, Size size, double textScale, Brightness brightness) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      // Thème sans police téléchargée : seuls les jetons de l'app comptent ici.
      theme: ThemeData(
        brightness: brightness,
        extensions: [brightness == Brightness.dark ? AppTokens.dark : AppTokens.light],
      ),
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(onPressed: () => showDemoPhotoPickerSheet(context), child: const Text('ouvrir')),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
  }

  const sizes = [Size(320, 568), Size(360, 740), Size(390, 844)];
  for (final size in sizes) {
    for (final scale in [1.0, 1.5]) {
      for (final brightness in Brightness.values) {
        testWidgets('${size.width.toInt()}×${size.height.toInt()}, texte ×$scale, ${brightness.name}', (tester) async {
          await open(tester, size, scale, brightness);
          expect(tester.takeException(), isNull);
          expect(find.text('Photos de démonstration'), findsOneWidget);
          expect(find.textContaining('${kAvailableDemoPhotos.length} photos'), findsOneWidget);

          final last = find.text(kAvailableDemoPhotos.last.title);
          await tester.scrollUntilVisible(
            last,
            120,
            scrollable: find.descendant(of: find.byKey(const Key('demo-photo-grid')), matching: find.byType(Scrollable)),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);

          // La dernière carte est entièrement visible dans la grille.
          final card = find.ancestor(of: last, matching: find.byType(InkWell)).first;
          final grid = tester.getRect(find.byKey(const Key('demo-photo-grid')));
          final rect = tester.getRect(card);
          expect(rect.top, greaterThanOrEqualTo(grid.top - 0.5));
          expect(rect.bottom, lessThanOrEqualTo(grid.bottom + 0.5));
          expect(rect.bottom, lessThanOrEqualTo(size.height));
          expect(last.hitTestable(), findsOneWidget);
        });
      }
    }
  }
}
