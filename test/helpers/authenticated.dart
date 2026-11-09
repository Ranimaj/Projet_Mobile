import 'package:campusconnect/core/theme/app_theme.dart';
import 'dart:async';

import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/providers/connectivity_provider.dart';
import 'package:campusconnect/services/auth_service.dart';
import 'package:campusconnect/services/device_session_service.dart';
import 'package:campusconnect/services/student_card_service.dart';
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
  final StreamController<AuthAccount?> _stream = StreamController<AuthAccount?>.broadcast();
  late final AuthProvider provider;

  /// Heure courante vue par le provider.
  DateTime now = DateTime(2026, 1, 1, 12);

  AuthHarness({StudentCardService? studentCardService, DeviceSessionService? deviceSessionService}) {
    when(() => service.authStateChanges).thenAnswer((_) => _stream.stream);
    when(() => service.watchProfile(any()))
        .thenAnswer((_) => const Stream<AppUser?>.empty().asBroadcastStream());
    when(() => connectivity.isOnline).thenReturn(true);
    when(() => service.twoFactorPending).thenReturn(false);
    when(() => service.demoSmsCode).thenReturn(null);
    provider = AuthProvider(
      authService: service,
      storageService: storage,
      studentCardService: studentCardService,
      deviceSessionService: deviceSessionService,
      clock: () => now,
    );
  }

  /// Ouvre la session de [user] ([sampleUser] par défaut). Avec
  /// [twoFactorPending], la connexion attend le code de double
  /// authentification.
  Future<void> signIn(WidgetTester tester, {AppUser? user, bool twoFactorPending = false}) async {
    final u = user ?? sampleUser;
    when(() => service.fetchProfile(u.id)).thenAnswer((_) async => u);
    when(() => service.twoFactorPending).thenReturn(twoFactorPending);
    await tester.runAsync(() async {
      _stream.add(AuthAccount(uid: u.id, email: u.email));
      await Future<void>.delayed(Duration.zero);
    });
    expect(provider.status, AuthStatus.authenticated);
  }

  /// Monte [screen]. Avec [push], l'écran est poussé au-dessus d'une page
  /// factice pour pouvoir vérifier les `pop`.
  Future<void> pump(WidgetTester tester, Widget screen,
      {bool push = true, Brightness brightness = Brightness.light}) async {
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
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
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
