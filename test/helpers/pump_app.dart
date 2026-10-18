import 'package:campusconnect/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Monte [screen] au-dessus d'une page d'accueil factice (pour pouvoir tester
/// les `pop`) avec un [AuthProvider] réel branché sur le service fourni.
Future<AuthProvider> pumpAuthScreen(
  WidgetTester tester,
  AuthProvider provider,
  Widget screen,
) async {
  tester.view.physicalSize = const Size(420, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>.value(
      value: provider,
      child: MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return provider;
}

/// Saisit [text] dans le n-ième `TextFormField` de l'écran.
Future<void> enterField(WidgetTester tester, int index, String text) async {
  final finder = find.byType(TextFormField).at(index);
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
}

Future<void> tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}
