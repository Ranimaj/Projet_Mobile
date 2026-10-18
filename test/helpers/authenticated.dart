import 'dart:async';

import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/providers/connectivity_provider.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'mocks.dart';

final sampleUser = AppUser(
  id: 'uid-1',
  fullName: 'Amel Ben Salah',
  email: 'amel@esprit.tn',
  major: 'Génie Logiciel',
  year: '3ème année',
  skills: const ['Flutter'],
  createdAt: DateTime(2024, 9, 1),
);

/// Session déjà ouverte : un [AuthProvider] réel branché sur un AuthService
/// mocké (profil chargé), un StorageService mocké, une horloge pilotable et
/// un ConnectivityProvider factice "en ligne".
class AuthHarness {
  final MockAuthService service = MockAuthService();
  final MockStorageService storage = MockStorageService();
  final MockConnectivityProvider connectivity = MockConnectivityProvider();
  final StreamController<User?> _stream = StreamController<User?>.broadcast();
  late final AuthProvider provider;

  /// Heure courante vue par le provider (délai de renvoi d'email...).
  DateTime now = DateTime(2026, 1, 1, 12);

  AuthHarness() {
    when(() => service.authStateChanges).thenAnswer((_) => _stream.stream);
    when(() => connectivity.isOnline).thenReturn(true);
    when(() => connectivity.pendingActionsCount).thenReturn(0);
    provider = AuthProvider(authService: service, storageService: storage, clock: () => now);
  }

  Future<void> signIn(
    WidgetTester tester, {
    AppUser? user,
    bool emailVerified = true,
    List<String> providers = const ['password'],
  }) async {
    final u = user ?? sampleUser;
    when(() => service.fetchProfile(u.id)).thenAnswer((_) async => u);
    await tester.runAsync(() async {
      _stream.add(MockUser(
        uid: u.id,
        email: u.email,
        isEmailVerified: emailVerified,
        providerData: [for (final p in providers) FakeUserInfo(p)],
      ));
      await Future<void>.delayed(Duration.zero);
    });
    expect(provider.status, AuthStatus.authenticated);
  }

  /// Monte [screen]. Avec [push], l'écran est poussé au-dessus d'une page
  /// factice pour pouvoir vérifier les `pop`.
  Future<void> pump(WidgetTester tester, Widget screen, {bool push = true}) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: provider),
          ChangeNotifierProvider<ConnectivityProvider>.value(value: connectivity),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: push ? _Launcher(screen) : screen,
        ),
      ),
    );
    if (push) await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> dispose() async {
    provider.dispose();
    await _stream.close();
  }
}

class _Launcher extends StatelessWidget {
  final Widget screen;
  const _Launcher(this.screen);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () =>
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen)),
          child: const Text('open'),
        ),
      ),
    );
  }
}
