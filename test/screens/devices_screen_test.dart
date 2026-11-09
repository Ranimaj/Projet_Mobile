import 'package:campusconnect/core/utils/auth_failure.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/screens/auth/otp_verification_screen.dart' show DemoSmsBanner;
import 'package:campusconnect/screens/security/confirm_device_screen.dart';
import 'package:campusconnect/screens/security/devices_screen.dart';
import 'package:campusconnect/services/device_session_service.dart';
import 'package:campusconnect/services/local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/authenticated.dart';
import '../helpers/local_db.dart';
import '../helpers/pump_themed.dart';

void main() {
  late DeviceSessionService me;
  late AuthHarness h;
  late DateTime now;

  setUp(() async {
    await openTestDatabase();
    now = DateTime(2026, 11, 9, 10, 30);
    me = DeviceSessionService(
      store: LocalStore(),
      deviceInfo: () async => (name: 'Pixel 8', platform: 'android'),
      city: () async => 'Tunis, Tunisie',
      clock: () => now,
    );
    // Identifiant du téléphone tiré ici (vraie asynchronie) : l'écrire dans
    // SQLite depuis un testWidgets bloquerait l'horloge factice.
    await me.currentDevice();
    h = AuthHarness(deviceSessionService: me);
  });
  tearDown(() async {
    await h.dispose();
    await closeTestDatabase();
  });

  /// [count] connexions de l'utilisateur sur ce téléphone, puis session ouverte.
  Future<void> signInWith(WidgetTester tester, {int count = 1}) async {
    await tester.runAsync(() async {
      for (var i = 0; i < count; i++) {
        now = now.add(const Duration(hours: 1));
        await me.recordLogin(sampleUser.id);
      }
    });
    await h.signIn(tester);
  }

  Finder loginRows() => find
      .byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('login-'));

  group('Mes appareils', () {
    testWidgets('shows this phone, the local-data note and the login history', (tester) async {
      await signInWith(tester, count: 2);
      await h.pump(tester, const DevicesScreen());

      expect(find.text('Mes appareils'), findsOneWidget);
      expect(find.byKey(const Key('this-device')), findsOneWidget);
      expect(find.text('Cet appareil'), findsOneWidget);
      expect(find.textContaining('Android'), findsOneWidget);
      expect(find.textContaining('Connecté depuis le'), findsOneWidget);
      expect(find.textContaining('Tunis, Tunisie'), findsWidgets);
      expect(find.byKey(const Key('devices-local-note')), findsOneWidget);
      expect(find.text('Historique des connexions'), findsOneWidget);
      expect(loginRows(), findsNWidgets(2));
      // Plus d'actions à distance : rien ne peut être fait sur un autre appareil.
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      expect(find.text('Déconnecter'), findsNothing);
    });

    testWidgets('only the logins of this account are listed, live', (tester) async {
      await signInWith(tester);
      await tester.runAsync(() => me.recordLogin('someone-else'));
      await h.pump(tester, const DevicesScreen());
      expect(loginRows(), findsOneWidget);

      await tester.runAsync(() async {
        now = now.add(const Duration(hours: 1));
        await me.recordLogin(sampleUser.id);
      });
      await tester.pumpAndSettle();
      expect(loginRows(), findsNWidgets(2));
    });

    testWidgets('empty history before any password login', (tester) async {
      await h.signIn(tester);
      await h.pump(tester, const DevicesScreen());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      expect(find.text('Pixel 8'), findsOneWidget);
      expect(find.text('Aucune connexion enregistrée.'), findsOneWidget);
    });

    testWidgets('readable text and 48 dp tap targets on a narrow phone', (tester) async {
      await signInWith(tester, count: 3);
      // Sans route en dessous : le bouton retour standard d'AppBar (zone d'appui
      // de 48 dp par MaterialTapTargetSize) n'est pas mesurable par le helper.
      await h.pump(tester, const DevicesScreen(), push: false);
      tester.view.physicalSize = const Size(360, 1400);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expectNoSmallText(tester);
      expectTapTargets(tester);
    });
  });

  group('Double authentification', () {
    final withPhone = sampleUser.copyWith(isPhoneVerified: true, phoneNumber: '+21698765432');

    setUp(() {
      when(() => h.service.sendPhoneOtp(any())).thenAnswer((_) async => '+21698765432');
      when(() => h.service.demoSmsCode).thenReturn('482913');
      when(() => h.service.signOut()).thenAnswer((_) async {});
    });

    Future<void> open(WidgetTester tester) async {
      await h.signIn(tester, user: withPhone, twoFactorPending: true);
      expect(h.provider.twoFactorRequired, isTrue);
      await h.pump(tester, const ConfirmDeviceScreen(), push: false);
    }

    testWidgets('sends the code to the verified phone and shows the simulated SMS', (tester) async {
      await open(tester);
      verify(() => h.service.sendPhoneOtp('+21698765432')).called(1);
      expect(find.textContaining('•• ••• 432'), findsWidgets);
      expect(find.textContaining('98765'), findsNothing);
      expect(find.byType(DemoSmsBanner), findsOneWidget);
      expect(find.text('SMS simulé : ton code est 482913'), findsOneWidget);
      expect(ConfirmDeviceScreen.maskPhone('+216 98 765 432'), '•• ••• 432');
    });

    testWidgets('the right code unlocks the app', (tester) async {
      when(() => h.service.verifyPhoneOtp(any())).thenAnswer((_) async {});
      await open(tester);
      await tester.enterText(find.byKey(const Key('otp-field')), '482913');
      await tester.pumpAndSettle();
      verify(() => h.service.verifyPhoneOtp('482913')).called(1);
      expect(h.provider.twoFactorRequired, isFalse);
    });

    testWidgets('a wrong code keeps the app locked and says why', (tester) async {
      final wrong = AuthFailure.fromCode('invalid-verification-code');
      when(() => h.service.verifyPhoneOtp(any())).thenThrow(wrong);
      await open(tester);
      await tester.enterText(find.byKey(const Key('otp-field')), '000000');
      await tester.pumpAndSettle();
      expect(h.provider.twoFactorRequired, isTrue);
      expect(find.text(wrong.message), findsOneWidget);
    });

    testWidgets('cancel logs out', (tester) async {
      await open(tester);
      await tester.ensureVisible(find.byKey(const Key('confirm-device-logout')));
      await tester.tap(find.byKey(const Key('confirm-device-logout')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      verify(() => h.service.signOut()).called(1);
      expect(h.provider.status, AuthStatus.visitor);
    });

    testWidgets('readable text and 48 dp tap targets', (tester) async {
      await open(tester);
      tester.view.physicalSize = const Size(360, 1400);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expectNoSmallText(tester);
      expectTapTargets(tester);
    });
  });
}
