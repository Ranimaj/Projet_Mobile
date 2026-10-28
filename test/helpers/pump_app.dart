import 'package:campusconnect/core/theme/app_theme.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Monte [screen] au-dessus d'une page d'accueil factice (pour pouvoir tester
/// les `pop`) avec un [AuthProvider] réel branché sur le service fourni.
/// [keyboardInset] simule un clavier ouvert ; [wrap] enveloppe l'application
/// (p. ex. pour injecter un `Provider`).
Future<AuthProvider> pumpAuthScreen(
  WidgetTester tester,
  AuthProvider provider,
  Widget screen, {
  Size size = const Size(420, 1000),
  Brightness brightness = Brightness.light,
  double keyboardInset = 0,
  Widget Function(Widget child)? wrap,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>.value(
      value: provider,
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(context).copyWith(viewInsets: EdgeInsets.only(bottom: keyboardInset)),
          child: wrap == null ? app! : wrap(app!),
        ),
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
