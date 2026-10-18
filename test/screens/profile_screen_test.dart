import 'package:campusconnect/core/utils/auth_failure.dart';
import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/screens/auth/otp_verification_screen.dart';
import 'package:campusconnect/screens/profile/change_password_screen.dart';
import 'package:campusconnect/screens/profile/edit_profile_screen.dart';
import 'package:campusconnect/screens/profile/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../helpers/authenticated.dart';
import '../helpers/pump_app.dart';

/// Même routage que `_RootRouter` dans main.dart : l'accueil connecté quand la
/// session est ouverte, l'écran visiteur sinon. Comme dans l'app, le profil
/// est *poussé* au-dessus de cette racine (voir [open]) — c'est ce qui a
/// révélé le bug « spinner infini après déconnexion ».
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      body: Center(child: Text(auth.status == AuthStatus.authenticated ? 'HOME' : 'VISITOR')),
    );
  }
}

void main() {
  late AuthHarness h;

  setUpAll(() => registerFallbackValue(sampleUser));

  setUp(() => h = AuthHarness());
  tearDown(() => h.dispose());

  Future<void> open(
    WidgetTester tester, {
    AppUser? user,
    bool emailVerified = true,
    List<String> providers = const ['password'],
  }) async {
    await h.signIn(tester, user: user, emailVerified: emailVerified, providers: providers);
    await h.pump(tester, const _Root(), push: false);
    Navigator.of(tester.element(find.text('HOME')))
        .push(MaterialPageRoute<void>(builder: (_) => const ProfileScreen()));
    await tester.pumpAndSettle();
  }

  group('header & badges', () {
    testWidgets('shows identity, initials and verification badges', (tester) async {
      await open(tester, user: sampleUser.copyWith(isVerifiedStudent: true, isPhoneVerified: true));

      expect(find.text('Amel Ben Salah'), findsOneWidget);
      expect(find.text('AS'), findsOneWidget);
      expect(find.text('Génie Logiciel · 3ème année'), findsOneWidget);
      expect(find.text('Étudiant vérifié'), findsOneWidget);
      expect(find.text('Email vérifié'), findsOneWidget);
      expect(find.text('Téléphone vérifié'), findsOneWidget);
      expect(find.text('Email non vérifié'), findsNothing);
    });

    testWidgets('pending states are shown when nothing is verified', (tester) async {
      await open(tester, emailVerified: false);

      expect(find.text('Vérification en attente'), findsOneWidget);
      expect(find.text('Email non vérifié'), findsOneWidget);
      expect(find.text('Aucun numéro vérifié'), findsOneWidget);
      expect(find.text('À vérifier'), findsOneWidget);
    });

    testWidgets('hides "Changer le mot de passe" for Google-only accounts', (tester) async {
      await open(tester, providers: const ['google.com']);
      expect(find.text('Changer le mot de passe'), findsNothing);
    });
  });

  group('email verification banner', () {
    testWidgets('"Renvoyer" sends the email and starts a countdown that ends with the cooldown',
        (tester) async {
      when(() => h.service.sendEmailVerification()).thenAnswer((_) async {});
      await open(tester, emailVerified: false);

      await tapText(tester, 'Renvoyer');
      await tester.pump();

      verify(() => h.service.sendEmailVerification()).called(1);
      expect(find.text('Email de vérification renvoyé.'), findsOneWidget);
      expect(find.text('Renvoyer (60 s)'), findsOneWidget);

      // Le bouton reste verrouillé tant que le délai court...
      await tester.tap(find.text('Renvoyer (60 s)'));
      await tester.pump();
      verifyNever(() => h.service.sendEmailVerification());

      // ...et se déverrouille une fois le délai écoulé.
      h.now = h.now.add(const Duration(seconds: 61));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Renvoyer'), findsOneWidget);
    });

    testWidgets('"J\'ai vérifié" reloads the user and removes the banner once verified',
        (tester) async {
      when(() => h.service.reloadUser()).thenAnswer((_) async => true);
      await open(tester, emailVerified: false);

      await tapText(tester, 'J\'ai vérifié');
      await tester.pumpAndSettle();

      expect(find.text('Email non vérifié'), findsNothing);
      expect(find.text('Email vérifié'), findsOneWidget);
    });

    testWidgets('"J\'ai vérifié" explains when the email is still unverified', (tester) async {
      when(() => h.service.reloadUser()).thenAnswer((_) async => false);
      await open(tester, emailVerified: false);

      await tapText(tester, 'J\'ai vérifié');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('toujours non vérifié'), findsOneWidget);
      expect(find.text('Email non vérifié'), findsOneWidget);
    });
  });

  group('navigation', () {
    testWidgets('opens the edit and change-password screens', (tester) async {
      await open(tester);

      await tapText(tester, 'Modifier mes informations');
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tapText(tester, 'Changer le mot de passe');
      await tester.pumpAndSettle();
      expect(find.byType(ChangePasswordScreen), findsOneWidget);
    });

    testWidgets('phone tile asks for a number, validates it and starts the OTP flow', (tester) async {
      when(() => h.service.sendPhoneOtp(any())).thenAnswer((_) async => '+21620123456');
      await open(tester);

      await tapText(tester, 'Numéro de téléphone');
      await tester.pumpAndSettle();
      expect(find.text('Vérifier mon numéro'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '12');
      await tapText(tester, 'Envoyer le code');
      await tester.pump();
      expect(find.text('Numéro invalide (ex. 20 123 456)'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), '20 123 456');
      await tapText(tester, 'Envoyer le code');
      await tester.pumpAndSettle();

      expect(find.byType(OtpVerificationScreen), findsOneWidget);
      verify(() => h.service.sendPhoneOtp('+21620123456')).called(1);
    });
  });

  group('security & session', () {
    testWidgets('the 2FA switch updates the profile', (tester) async {
      when(() => h.service.updateProfile(any()))
          .thenAnswer((inv) async => inv.positionalArguments.first as AppUser);
      await open(tester);

      await tester.ensureVisible(find.byType(Switch));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      final saved = verify(() => h.service.updateProfile(captureAny())).captured.single as AppUser;
      expect(saved.twoFactorEnabled, isTrue);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });

    testWidgets('logout signs out and leaves the profile route', (tester) async {
      when(() => h.service.signOut()).thenAnswer((_) async {});
      await open(tester);

      await tapText(tester, 'Déconnexion');
      await tester.pumpAndSettle();

      verify(() => h.service.signOut()).called(1);
      expect(h.provider.status, AuthStatus.visitor);
      expect(find.byType(ProfileScreen), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('VISITOR'), findsOneWidget);
    });

    testWidgets('a failed logout keeps the user on the profile', (tester) async {
      when(() => h.service.signOut()).thenThrow(AuthFailure.fromCode('network-request-failed'));
      await open(tester);

      await tapText(tester, 'Déconnexion');
      await tester.pumpAndSettle();

      expect(h.provider.status, AuthStatus.authenticated);
      expect(find.byType(ProfileScreen), findsOneWidget);
    });
  });

  group('data & privacy', () {
    testWidgets('export shows the JSON and copies it', (tester) async {
      // Le presse-papiers passe par un canal natif : on l'intercepte.
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() =>
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      when(() => h.service.exportUserData('uid-1')).thenAnswer((_) async => {
            'account': {'email': 'amel@esprit.tn'},
            'profile': {'fullName': 'Amel Ben Salah'},
          });
      await open(tester);

      await tapText(tester, 'Exporter mes données (RGPD)');
      await tester.pumpAndSettle();

      expect(find.text('Mes données'), findsOneWidget);
      expect(find.textContaining('"email": "amel@esprit.tn"'), findsOneWidget);

      await tapText(tester, 'Copier');
      await tester.pumpAndSettle();
      expect(find.text('Mes données'), findsNothing);
      expect(find.text('Données copiées dans le presse-papiers.'), findsOneWidget);
      expect(copied, contains('"fullName": "Amel Ben Salah"'));
    });

    testWidgets('export failure is reported', (tester) async {
      when(() => h.service.exportUserData(any())).thenThrow(AuthFailure.fromCode('network-request-failed'));
      await open(tester);

      await tapText(tester, 'Exporter mes données (RGPD)');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Pas de connexion réseau.'), findsOneWidget);
      expect(find.text('Mes données'), findsNothing);
    });

    testWidgets('deletion requires the password and reports a wrong one inside the dialog',
        (tester) async {
      when(() => h.service.deleteAccount(password: any(named: 'password')))
          .thenThrow(AuthFailure.fromCode('wrong-password'));
      await open(tester);

      await tapText(tester, 'Supprimer mon compte');
      await tester.pumpAndSettle();
      expect(find.text('Supprimer le compte'), findsOneWidget);

      await tapText(tester, 'Supprimer définitivement');
      await tester.pump();
      expect(find.text('Mot de passe requis'), findsOneWidget);
      verifyNever(() => h.service.deleteAccount(password: any(named: 'password')));

      await tester.enterText(find.byType(TextFormField).last, 'bad');
      await tapText(tester, 'Supprimer définitivement');
      await tester.pumpAndSettle();

      verify(() => h.service.deleteAccount(password: 'bad')).called(1);
      expect(find.text('Email ou mot de passe incorrect.'), findsOneWidget);
      expect(find.text('Supprimer le compte'), findsOneWidget); // le dialogue reste ouvert
      expect(h.provider.status, AuthStatus.authenticated);
    });

    testWidgets('a confirmed deletion closes the dialog and ends the session', (tester) async {
      when(() => h.service.deleteAccount(password: 'secret123')).thenAnswer((_) async {});
      await open(tester);

      await tapText(tester, 'Supprimer mon compte');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).last, 'secret123');
      await tapText(tester, 'Supprimer définitivement');
      await tester.pumpAndSettle();

      verify(() => h.service.deleteAccount(password: 'secret123')).called(1);
      expect(find.text('Supprimer le compte'), findsNothing);
      expect(h.provider.status, AuthStatus.visitor);
      expect(find.byType(ProfileScreen), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('VISITOR'), findsOneWidget);
    });

    testWidgets('Google-only accounts delete without a password field', (tester) async {
      when(() => h.service.deleteAccount(password: null)).thenAnswer((_) async {});
      await open(tester, providers: const ['google.com']);

      await tapText(tester, 'Supprimer mon compte');
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);

      await tapText(tester, 'Supprimer définitivement');
      await tester.pumpAndSettle();
      verify(() => h.service.deleteAccount(password: null)).called(1);
    });
  });
}
