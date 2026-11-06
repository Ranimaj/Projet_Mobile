import 'package:campusconnect/core/theme/app_theme.dart';
import 'package:campusconnect/providers/article_provider.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/providers/connectivity_provider.dart';
import 'package:campusconnect/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'articles.dart';
import 'authenticated.dart';
import 'mocks.dart';

/// Provider Vente & Don réel branché sur un dépôt en mémoire.
ArticleProvider marketProvider(FakeArticleRepo repo,
        {LocationLookup? locate, bool online = true, FakePhotoStore? photos}) =>
    ArticleProvider(
      repository: repo,
      storage: MockStorageService(),
      locate: locate ?? () async => const LocationResult.failed(LocationFailure.denied),
      photos: photos ?? FakePhotoStore(),
      patchQueued: (_, __) async {},
    )..updateConnectivity(online);

/// Monte [screen] (poussé au-dessus d'une page « open ») avec l'auth, le
/// réseau et le provider Vente & Don. Charge les articles avant l'affichage.
Future<void> pumpMarket(
  WidgetTester tester,
  AuthHarness h,
  ArticleProvider articles,
  Widget screen, {
  Size size = const Size(420, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.runAsync(articles.load);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: h.provider),
        ChangeNotifierProvider<ConnectivityProvider>.value(value: h.connectivity),
        ChangeNotifierProvider<ArticleProvider>.value(value: articles),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)),
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
}
