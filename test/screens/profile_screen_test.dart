import 'package:campusconnect/core/theme/app_theme.dart';
import 'package:campusconnect/core/utils/auth_failure.dart';
import 'package:campusconnect/models/annonce_model.dart';
import 'package:campusconnect/models/job_offer_model.dart';
import 'package:campusconnect/models/article_model.dart';
import 'package:campusconnect/models/user_model.dart';
import 'package:campusconnect/providers/annonce_provider.dart';
import 'package:campusconnect/providers/article_provider.dart';
import 'package:campusconnect/providers/auth_provider.dart';
import 'package:campusconnect/providers/connectivity_provider.dart';
import 'package:campusconnect/providers/job_provider.dart';
import 'package:campusconnect/providers/theme_provider.dart';
import 'package:campusconnect/screens/auth/otp_verification_screen.dart';
import 'package:campusconnect/screens/debug/design_gallery_screen.dart';
import 'package:campusconnect/screens/profile/change_password_screen.dart';
import 'package:campusconnect/screens/profile/edit_profile_screen.dart';
import 'package:campusconnect/screens/profile/profile_screen.dart';
import 'package:campusconnect/services/app_prefs.dart';
import 'package:campusconnect/widgets/initials_avatar.dart';
import 'package:campusconnect/widgets/setting_row.dart';
import 'package:campusconnect/widgets/stat_tile.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/authenticated.dart';
import '../helpers/pump_app.dart';
import '../helpers/pump_themed.dart';

class _MockArticles extends Mock implements ArticleProvider {}

class _MockAnnonces extends Mock implements AnnonceProvider {}

class _MockJobs extends Mock implements JobProvider {}

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
      body: Center(
          child: Text(
              auth.status == AuthStatus.authenticated ? 'HOME' : 'VISITOR')),
    );
  }
}

ApplicationModel _application(String id) => ApplicationModel(
    id: id,
    jobOfferId: 'o$id',
    jobTitle: 't',
    companyName: 'c',
    candidateId: 'uid-1',
    appliedAt: DateTime(2026));

AppUser _admin({StudentCard studentCard = StudentCard.none}) => AppUser(
    id: sampleUser.id,
    fullName: sampleUser.fullName,
    email: sampleUser.email,
    major: sampleUser.major,
    year: sampleUser.year,
    role: UserRole.admin,
    studentCard: studentCard,
    createdAt: sampleUser.createdAt);

void main() {
  late AuthHarness h;
  late _MockArticles articles;
  late _MockAnnonces annonces;
  late _MockJobs jobs;
  late AppPrefs prefs;
  late ThemeProvider theme;

  setUpAll(() async {
    registerFallbackValue(sampleUser);
    await initializeDateFormatting('fr_FR');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = AppPrefs(await SharedPreferences.getInstance());
    theme = ThemeProvider(prefs);
    h = AuthHarness();
    articles = _MockArticles();
    annonces = _MockAnnonces();
    jobs = _MockJobs();
    when(() => articles.items).thenReturn(const []);
    when(() => annonces.items).thenReturn(const []);
    when(() => jobs.myApplications).thenReturn(const []);
  });
  tearDown(() => h.dispose());

  Future<void> open(
    WidgetTester tester, {
    AppUser? user,
    bool emailVerified = true,
    List<String> providers = const ['password'],
    Brightness brightness = Brightness.light,
    Size size = const Size(420, 2600),
    double textScale = 1,
  }) async {
    await tester.pumpWidget(const SizedBox());
    await h.signIn(tester,
        user: user, emailVerified: emailVerified, providers: providers);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: h.provider),
          ChangeNotifierProvider<ConnectivityProvider>.value(
              value: h.connectivity),
          ChangeNotifierProvider<ArticleProvider>.value(value: articles),
          ChangeNotifierProvider<AnnonceProvider>.value(value: annonces),
          ChangeNotifierProvider<JobProvider>.value(value: jobs),
          Provider<AppPrefs>.value(value: prefs),
          ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode:
              brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
          builder: (context, app) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: app!,
          ),
          home: const _Root(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('HOME')))
        .push(MaterialPageRoute<void>(builder: (_) => const ProfileScreen()));
    await tester.pumpAndSettle();
  }

  AppUser withCard(StudentCardStatus status) =>
      sampleUser.copyWith(studentCard: StudentCard(status: status));

  group('header & chips', () {
    testWidgets('shows identity, initials and verification chips',
        (tester) async {
      await open(tester,
          user: sampleUser.copyWith(
              isPhoneVerified: true,
              studentCard:
                  const StudentCard(status: StudentCardStatus.verified)));

      expect(find.text('Amel Ben Salah'), findsOneWidget);
      expect(find.text('AS'), findsOneWidget);
      expect(find.text('Génie Logiciel · 3ème année'), findsOneWidget);
      expect(find.text('Étudiant vérifié'), findsOneWidget);
      expect(find.text('Email vérifié'), findsOneWidget);
      expect(find.text('Téléphone vérifié'), findsOneWidget);
      expect(find.text('Email non vérifié'), findsNothing);
    });

    testWidgets('one chip per student-card status', (tester) async {
      await open(tester, user: withCard(StudentCardStatus.none));
      expect(find.text('Étudiant vérifié'), findsNothing);
      expect(find.text('Vérification en attente'), findsNothing);
      expect(find.text('Carte refusée'), findsNothing);

      await open(tester, user: withCard(StudentCardStatus.pending));
      expect(find.text('Vérification en attente'), findsOneWidget);

      await open(tester, user: withCard(StudentCardStatus.verified));
      expect(find.text('Étudiant vérifié'), findsOneWidget);

      await open(tester, user: withCard(StudentCardStatus.rejected));
      expect(find.text('Carte refusée'), findsOneWidget);
    });

    testWidgets('unverified email and phone are flagged', (tester) async {
      await open(tester, emailVerified: false);

      expect(find.text('Email à vérifier'), findsOneWidget);
      expect(find.text('Email non vérifié'), findsOneWidget); // bandeau
      expect(find.text('Aucun numéro vérifié'), findsOneWidget);
      expect(find.text('À vérifier'), findsOneWidget);
      expect(find.text('Téléphone vérifié'), findsNothing);
    });

    testWidgets(
        'stats come from the notices, articles and applications of the user',
        (tester) async {
      AnnonceModel notice(String id, String author) => AnnonceModel(
          id: id,
          authorId: author,
          authorName: 'x',
          title: 't',
          content: '',
          category: 'c',
          createdAt: DateTime(2026));
      ArticleModel article(String id, String owner) => ArticleModel(
          id: id,
          ownerId: owner,
          ownerName: 'x',
          title: 't',
          description: '',
          category: 'c',
          createdAt: DateTime(2026));
      when(() => annonces.items).thenReturn(
          [notice('1', 'uid-1'), notice('2', 'other'), notice('3', 'uid-1')]);
      when(() => articles.items).thenReturn([article('1', 'uid-1')]);
      when(() => jobs.myApplications).thenReturn([
        _application('1'),
        _application('2'),
        _application('3'),
        _application('4')
      ]);
      await open(tester);

      String valueOf(String label) {
        final tile = find.ancestor(
            of: find.text(label), matching: find.byType(StatTile));
        return tester.widget<StatTile>(tile).value;
      }

      expect(valueOf('Annonces'), '2');
      expect(valueOf('Ventes'), '1');
      expect(valueOf('Candidatures'), '4');
    });

    testWidgets('the avatar straddles the top edge of the sheet',
        (tester) async {
      await open(tester);
      final avatar = tester.getRect(find.byType(InitialsAvatar));
      final heroBottom = tester.getBottomLeft(find.byType(Image)).dy;
      expect(avatar.top, lessThan(heroBottom - 28));
      expect(avatar.bottom, greaterThan(heroBottom - 28));
    });

    testWidgets('a rejected card shows its reason', (tester) async {
      await open(tester,
          user: sampleUser.copyWith(
              studentCard: const StudentCard(
                  status: StudentCardStatus.rejected,
                  rejectReason: 'Photo floue')));
      expect(find.text('Refusée : Photo floue'), findsOneWidget);
    });

    testWidgets('bottom bar shows the member since date and the edit button',
        (tester) async {
      await open(tester);

      expect(find.text('Membre depuis sept. 2024'), findsOneWidget);
      await tapText(tester, 'Modifier le profil');
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsOneWidget);
    });

    testWidgets('the share action copies the profile text', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await open(tester);

      await tester.tap(find.byTooltip('Partager'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(copied, 'Amel Ben Salah · Génie Logiciel · 3ème année');
      expect(find.text('Profil copié'), findsOneWidget);
    });

    testWidgets('hides "Changer le mot de passe" for Google-only accounts',
        (tester) async {
      await open(tester, providers: const ['google.com']);
      expect(find.text('Changer le mot de passe'), findsNothing);
    });
  });

  group('email verification banner', () {
    testWidgets(
        '"Renvoyer" sends the email and starts a countdown that ends with the cooldown',
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

    testWidgets(
        '"J\'ai vérifié" reloads the user and removes the banner once verified',
        (tester) async {
      when(() => h.service.reloadUser()).thenAnswer((_) async => true);
      await open(tester, emailVerified: false);

      await tapText(tester, 'J\'ai vérifié');
      await tester.pumpAndSettle();

      expect(find.text('Email non vérifié'), findsNothing);
      expect(find.text('Email vérifié'), findsOneWidget);
    });

    testWidgets('"J\'ai vérifié" explains when the email is still unverified',
        (tester) async {
      when(() => h.service.reloadUser()).thenAnswer((_) async => false);
      await open(tester, emailVerified: false);

      await tapText(tester, 'J\'ai vérifié');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('toujours non vérifié'), findsOneWidget);
      expect(find.text('Email non vérifié'), findsOneWidget);
    });
  });

  group('preferences & roles', () {
    testWidgets('student card row reflects the status', (tester) async {
      await open(tester, user: withCard(StudentCardStatus.rejected));
      expect(find.text('Carte étudiant'), findsOneWidget);
      expect(find.text('Carte refusée'), findsOneWidget); // chip
      expect(find.textContaining('envoie-la à nouveau'),
          findsOneWidget); // sous-titre
    });

    testWidgets('the biometric switch persists through AppPrefs',
        (tester) async {
      await open(tester);
      final row = find.ancestor(
          of: find.text('Connexion biométrique'),
          matching: find.byType(SettingRow));
      final toggle = find.descendant(of: row, matching: find.byType(Switch));
      expect(tester.widget<Switch>(toggle).value, isTrue);

      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(prefs.biometricUnlock, isFalse);
      expect(tester.widget<Switch>(toggle).value, isFalse);
    });

    testWidgets('the theme sheet changes the ThemeProvider mode',
        (tester) async {
      await open(tester);
      expect(find.text('Système'), findsOneWidget);

      await tapText(tester, 'Thème');
      await tester.pumpAndSettle();
      expect(find.byType(RadioListTile<ThemeMode>), findsNWidgets(3));

      await tester.tap(find.widgetWithText(RadioListTile<ThemeMode>, 'Sombre'));
      await tester.pumpAndSettle();

      expect(theme.mode, ThemeMode.dark);
      expect(prefs.themeMode, ThemeMode.dark);
      expect(find.byType(RadioListTile<ThemeMode>), findsNothing);
      expect(find.text('Sombre'), findsOneWidget);
    });

    testWidgets('debug builds link the design gallery from "Sécurité"',
        (tester) async {
      expect(kDebugMode, isTrue);
      await open(tester);
      final row = find.widgetWithText(SettingRow, 'Galerie du design');
      expect(row, findsOneWidget);
      expect(
          find.descendant(
              of: find.ancestor(of: row, matching: find.byType(SettingGroup)),
              matching: find.text('Sécurité')),
          findsOneWidget);
      await tester.ensureVisible(row);
      await tester.tap(row);
      // The gallery shows looping skeletons: pump past the route transition.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(DesignGalleryScreen), findsOneWidget);
    });

    testWidgets('the administration group is only shown to admins',
        (tester) async {
      await open(tester);
      expect(find.text('Administration'), findsNothing);

      await open(tester, user: _admin());
      await tester.ensureVisible(find.text('Administration'));
      expect(find.text('Utilisateurs'), findsOneWidget);
      expect(find.text('Cartes à vérifier'), findsOneWidget);
      expect(find.text('Statistiques'), findsOneWidget);
    });
  });

  group('layout & accessibility', () {
    testWidgets(
        'the bottom bar wraps without overflow at 360 x 640 and text scale 1.3',
        (tester) async {
      await open(tester, size: const Size(360, 640), textScale: 1.3);
      expect(tester.takeException(), isNull);
      expect(find.text('Modifier le profil'), findsOneWidget);
      expect(find.textContaining('Membre depuis'), findsOneWidget);
    });

    testWidgets(
        'once scrolled, the avatar no longer covers the "Thème" row '
        '(360 x 640)', (tester) async {
      await open(tester, size: const Size(360, 640));
      final avatarAtRest = tester.getRect(find.byType(InitialsAvatar));
      final list = tester.state<ScrollableState>(find
          .descendant(
              of: find.byType(ListView), matching: find.byType(Scrollable))
          .first);
      final themeRow = find.widgetWithText(SettingRow, 'Thème');

      Future<void> scrollTo(double offset) async {
        list.position.jumpTo(offset);
        await tester.pumpAndSettle();
        final avatar = find.byType(InitialsAvatar);
        if (avatar.evaluate().isNotEmpty) {
          expect(tester.getRect(avatar).overlaps(tester.getRect(themeRow)),
              isFalse);
        }
      }

      await scrollTo(200);
      // Bring the row's icon under the part of the sheet the pinned avatar
      // used to cover.
      final icon = find.descendant(
          of: themeRow, matching: find.byIcon(Icons.brightness_6_rounded));
      final target = Offset(
          tester.getCenter(icon).dx, avatarAtRest.bottom - 12);
      await scrollTo(200 + tester.getCenter(icon).dy - target.dy);
      expect(avatarAtRest.contains(tester.getCenter(icon)), isTrue);

      // Tapping there reaches the row.
      await tester.tapAt(tester.getCenter(icon));
      await tester.pumpAndSettle();
      expect(find.byType(RadioListTile<ThemeMode>), findsNWidgets(3));
    });

    for (final brightness in Brightness.values) {
      testWidgets('no small text and 48 dp tap targets (${brightness.name})',
          (tester) async {
        await open(tester,
            brightness: brightness,
            emailVerified: false,
            user: _admin(
                studentCard:
                    const StudentCard(status: StudentCardStatus.pending)));
        expectNoSmallText(tester);
        expectTapTargets(tester);
      });
    }
  });

  group('navigation', () {
    testWidgets('opens the edit and change-password screens', (tester) async {
      await open(tester);

      await tapText(tester, 'Modifier mes informations');
      await tester.pumpAndSettle();
      expect(find.byType(EditProfileScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Retour').last);
      await tester.pumpAndSettle();

      await tapText(tester, 'Changer le mot de passe');
      await tester.pumpAndSettle();
      expect(find.byType(ChangePasswordScreen), findsOneWidget);
    });

    testWidgets(
        'phone tile asks for a number, validates it and starts the OTP flow',
        (tester) async {
      when(() => h.service.sendPhoneOtp(any()))
          .thenAnswer((_) async => '+21620123456');
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

      final row = find.ancestor(
          of: find.text('Authentification à deux facteurs'),
          matching: find.byType(SettingRow));
      final toggle = find.descendant(of: row, matching: find.byType(Switch));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      final saved = verify(() => h.service.updateProfile(captureAny()))
          .captured
          .single as AppUser;
      expect(saved.twoFactorEnabled, isTrue);
      expect(tester.widget<Switch>(toggle).value, isTrue);
    });

    testWidgets('logout signs out and leaves the profile route',
        (tester) async {
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

    testWidgets('a failed logout keeps the user on the profile',
        (tester) async {
      when(() => h.service.signOut())
          .thenThrow(AuthFailure.fromCode('network-request-failed'));
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
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

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
      expect(
          find.text('Données copiées dans le presse-papiers.'), findsOneWidget);
      expect(copied, contains('"fullName": "Amel Ben Salah"'));
    });

    testWidgets('export failure is reported', (tester) async {
      when(() => h.service.exportUserData(any()))
          .thenThrow(AuthFailure.fromCode('network-request-failed'));
      await open(tester);

      await tapText(tester, 'Exporter mes données (RGPD)');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Pas de connexion réseau.'), findsOneWidget);
      expect(find.text('Mes données'), findsNothing);
    });

    testWidgets(
        'deletion requires the password and reports a wrong one inside the dialog',
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
      verifyNever(
          () => h.service.deleteAccount(password: any(named: 'password')));

      await tester.enterText(find.byType(TextFormField).last, 'bad');
      await tapText(tester, 'Supprimer définitivement');
      await tester.pumpAndSettle();

      verify(() => h.service.deleteAccount(password: 'bad')).called(1);
      expect(find.text('Email ou mot de passe incorrect.'), findsOneWidget);
      expect(find.text('Supprimer le compte'),
          findsOneWidget); // le dialogue reste ouvert
      expect(h.provider.status, AuthStatus.authenticated);
    });

    testWidgets('a confirmed deletion closes the dialog and ends the session',
        (tester) async {
      when(() => h.service.deleteAccount(password: 'secret123'))
          .thenAnswer((_) async {});
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

    testWidgets('Google-only accounts delete without a password field',
        (tester) async {
      when(() => h.service.deleteAccount(password: null))
          .thenAnswer((_) async {});
      await open(tester, providers: const ['google.com']);

      await tapText(tester, 'Supprimer mon compte');
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);

      await tapText(tester, 'Supprimer définitivement');
      await tester.pumpAndSettle();
      verify(() => h.service.deleteAccount(password: null)).called(1);
    });
  });

  group('email verification confirms itself', () {
    testWidgets(
        're-checks in the background every 10 s and removes the banner once verified',
        (tester) async {
      var verified = false;
      when(() => h.service.reloadUser()).thenAnswer((_) async => verified);
      await open(tester, emailVerified: false);
      expect(find.text('Email non vérifié'), findsOneWidget);

      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      verify(() => h.service.reloadUser()).called(1); // sans aucun tap
      expect(find.text('Email non vérifié'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'vérification silencieuse');

      verified = true; // l'utilisateur a cliqué sur le lien dans sa boîte mail
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();

      expect(find.text('Email non vérifié'), findsNothing);
      expect(find.text('Email vérifié'), findsOneWidget);
    });

    testWidgets('re-checks when the app comes back to the foreground',
        (tester) async {
      when(() => h.service.reloadUser()).thenAnswer((_) async => true);
      await open(tester, emailVerified: false);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      verify(() => h.service.reloadUser()).called(1);
      expect(find.text('Email vérifié'), findsOneWidget);
    });

    testWidgets('a background check that fails stays silent', (tester) async {
      when(() => h.service.reloadUser())
          .thenThrow(AuthFailure.fromCode('network-request-failed'));
      await open(tester, emailVerified: false);

      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();

      expect(find.text('Pas de connexion réseau.'), findsNothing);
      expect(find.text('Email non vérifié'), findsOneWidget);
    });
  });
}
