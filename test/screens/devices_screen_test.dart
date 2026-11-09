import 'package:campusconnect/screens/security/confirm_device_screen.dart';
import 'package:campusconnect/screens/security/devices_screen.dart';
import 'package:campusconnect/screens/security/new_device_alert.dart';
import 'package:campusconnect/services/device_session_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/authenticated.dart';
import '../helpers/pump_themed.dart';

void main() {
  late FakeFirebaseFirestore db;
  late DeviceSessionService me;
  late AuthHarness h;

  DeviceSessionService phone(String name, {String? city}) {
    SharedPreferences.setMockInitialValues({});
    final prefs = SharedPreferences.getInstance();
    return DeviceSessionService(
      firestore: db,
      deviceInfo: () async => (name: name, platform: name.startsWith('Mac') ? 'macos' : 'android'),
      city: () async => city,
      prefs: () => prefs,
    );
  }

  setUp(() {
    db = FakeFirebaseFirestore();
    me = phone('Pixel 8', city: 'Tunis, Tunisie');
    h = AuthHarness(deviceSessionService: me);
  });
  tearDown(() => h.dispose());

  /// Ouvre la session sur « Pixel 8 », puis connecte [others].
  Future<void> signInWith(WidgetTester tester, List<String> others) async {
    await tester.runAsync(() async {
      await me.onSignedIn(sampleUser.id, twoFactor: false);
      for (final o in others) {
        await phone(o).onSignedIn(sampleUser.id, twoFactor: false);
      }
    });
    await h.signIn(tester);
  }

  testWidgets('lists this device first, the others, and the login history', (tester) async {
    await signInWith(tester, ['MacBook Air']);
    await h.pump(tester, const DevicesScreen());

    expect(find.text('Pixel 8'), findsWidgets);
    expect(find.text('Cet appareil'), findsOneWidget);
    expect(find.text('MacBook Air'), findsWidgets);
    expect(find.text('Nouveau'), findsOneWidget); // alerte pas encore confirmée
    expect(find.textContaining('Tunis, Tunisie'), findsWidgets);
    expect(find.text('Historique des connexions'), findsOneWidget);
    expect(find.byKey(const Key('revoke-others')), findsOneWidget);
  });

  testWidgets('readable text and 48 dp tap targets on a narrow phone', (tester) async {
    await signInWith(tester, ['Samsung Galaxy S23 Ultra', 'MacBook Air']);
    // Sans route en dessous : le bouton retour standard d'AppBar (zone d'appui
    // de 48 dp par MaterialTapTargetSize) n'est pas mesurable par le helper.
    await h.pump(tester, const DevicesScreen(), push: false);
    tester.view.physicalSize = const Size(360, 1400);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expectNoSmallText(tester);
    expectTapTargets(tester);
  });

  testWidgets('disconnecting another device asks first, then revokes it', (tester) async {
    await signInWith(tester, ['MacBook Air']);
    await h.pump(tester, const DevicesScreen());

    final mac = (await tester.runAsync(() => db.collection('users/uid-1/devices').get()))!
        .docs
        .firstWhere((d) => d['name'] == 'MacBook Air')
        .id;
    await tester.tap(find.byKey(Key('device-menu-$mac')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Déconnecter').last);
    await tester.pumpAndSettle();
    expect(find.text('Déconnecter MacBook Air ?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('confirm-action')));
    await tester.pumpAndSettle();

    final doc = await tester.runAsync(() => db.doc('users/uid-1/devices/$mac').get());
    expect(doc!['revoked'], isTrue);
    expect(find.text('Fermée à distance'), findsOneWidget);
    expect(find.byKey(const Key('revoke-others')), findsNothing);
    // La liste a changé de forme : l'historique doit rester affiché.
    await tester.scrollUntilVisible(find.text('Historique des connexions'), 200);
    expect(find.text('Aucune connexion enregistrée.'), findsNothing);
    expect(
        find.byWidgetPredicate(
            (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('login-')),
        findsNWidgets(2));
  });

  testWidgets('a new device triggers the alert; "Non" revokes it', (tester) async {
    await signInWith(tester, ['iPhone 15']);
    await h.pump(tester, const NewDeviceAlert(child: Scaffold(body: Text('accueil'))), push: false);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('new-device-alert')), findsOneWidget);
    expect(find.textContaining('iPhone 15'), findsOneWidget);
    await tester.tap(find.byKey(const Key('new-device-not-me')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();

    final docs = (await tester.runAsync(() => db.collection('users/uid-1/devices').get()))!.docs;
    expect(docs.firstWhere((d) => d['name'] == 'iPhone 15')['revoked'], isTrue);
    expect(find.text('Appareil déconnecté'), findsOneWidget); // propose de changer le mot de passe
  });

  testWidgets('"Oui, c\'est moi" just clears the alert', (tester) async {
    await signInWith(tester, ['iPhone 15']);
    await h.pump(tester, const NewDeviceAlert(child: Scaffold(body: Text('accueil'))), push: false);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('new-device-me')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));

    final docs = (await tester.runAsync(() => db.collection('users/uid-1/devices').get()))!.docs;
    final iphone = docs.firstWhere((d) => d['name'] == 'iPhone 15');
    expect(iphone['alertPending'], isFalse);
    expect(iphone['revoked'], isFalse);
  });

  testWidgets('the confirm-device screen masks the phone and offers the SMS', (tester) async {
    await h.signIn(tester, user: sampleUser.copyWith(isPhoneVerified: true, phoneNumber: '+21698765432'));
    await h.pump(tester, const ConfirmDeviceScreen(), push: false);
    expect(find.textContaining('•• ••• 432'), findsOneWidget);
    expect(find.textContaining('98765'), findsNothing);
    expect(find.byKey(const Key('confirm-device-sms')), findsOneWidget);
    expect(ConfirmDeviceScreen.maskPhone('+216 98 765 432'), '•• ••• 432');
  });
}
