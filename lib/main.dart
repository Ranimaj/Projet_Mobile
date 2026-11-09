import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/local_database.dart';
import 'providers/auth_provider.dart';
import 'providers/connectivity_provider.dart';
import 'providers/article_provider.dart';
import 'providers/annonce_provider.dart';
import 'providers/event_provider.dart';
import 'providers/job_provider.dart';
import 'providers/theme_provider.dart';
import 'services/app_prefs.dart';
import 'services/demo_seed.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/visitor/visitor_home_screen.dart';
import 'screens/home/app_shell.dart';
import 'screens/security/confirm_device_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');

  // Base SQLite de l'app (comptes, profils, annonces, événements, offres,
  // préférences) : chargée en mémoire une fois, avant le premier écran. Il
  // n'y a pas de serveur ; Vente & Don a sa propre base (ArticleDatabase).
  await LocalDatabase.open();
  // Anciens fichiers Hive (versions précédentes de l'app) : leurs données ne
  // sont pas reprises, on libère simplement la place, sans bloquer le démarrage.
  unawaited(LocalDatabase.deleteLegacyHiveFiles());
  // Premier lancement : comptes et contenus de démonstration.
  await DemoSeed().ensureSeeded();

  final prefs = await AppPrefs.load();

  runApp(CampusConnectApp(prefs: prefs));
}

class CampusConnectApp extends StatelessWidget {
  const CampusConnectApp({super.key, required this.prefs});

  final AppPrefs prefs;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppPrefs>.value(value: prefs),
        ChangeNotifierProvider(create: (_) => ThemeProvider(prefs)),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),

        // Chaque provider de module reçoit l'état réseau courant pour
        // basculer entre écriture directe et file d'attente locale.
        ChangeNotifierProxyProvider<ConnectivityProvider, ArticleProvider>(
          create: (_) => ArticleProvider(),
          update: (_, connectivity, provider) =>
              provider!..updateConnectivity(connectivity.isOnline),
        ),
        ChangeNotifierProxyProvider<ConnectivityProvider, AnnonceProvider>(
          create: (_) => AnnonceProvider(),
          update: (_, connectivity, provider) =>
              provider!..updateConnectivity(connectivity.isOnline),
        ),
        ChangeNotifierProxyProvider<ConnectivityProvider, EventProvider>(
          create: (_) => EventProvider(),
          update: (_, connectivity, provider) =>
              provider!..updateConnectivity(connectivity.isOnline),
        ),
        ChangeNotifierProxyProvider<ConnectivityProvider, JobProvider>(
          create: (_) => JobProvider(),
          update: (_, connectivity, provider) =>
              provider!..updateConnectivity(connectivity.isOnline),
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, theme, _) => MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: theme.mode,
          home: const RootRouter(),
        ),
      ),
    );
  }
}

/// Bascule entre l'onboarding, l'écran Visiteur et l'app connectée.
///
/// Stateful : les callbacks de l'onboarding appellent `setState` pour relire
/// `prefs.onboardingSeen`, de sorte que l'accueil visiteur apparaît dès que
/// l'écran de connexion/inscription poussé est refermé.
class RootRouter extends StatefulWidget {
  const RootRouter({super.key});

  @override
  State<RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<RootRouter> {
  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    setState(() {});
  }

  bool _announced = false;

  /// Un compte désactivé par un admin est déconnecté d'office : on
  /// l'explique une seule fois sur l'accueil visiteur, puis on efface le
  /// message.
  void _announceDisabledAccount(AuthProvider auth) {
    if (auth.errorCode != AuthProvider.accountDisabledCode) {
      _announced = false; // a later disable is announced again
      return;
    }
    // Several builds can happen before the error is cleared: one snack only.
    if (_announced) return;
    _announced = true;
    final message = auth.errorMessage;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Les écrans ouverts par-dessus (profil, administration, dialogues)
      // appartiennent à la session fermée : retour à l'accueil visiteur.
      Navigator.of(context).popUntil((route) => route.isFirst);
      if (message != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
      auth.clearError();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final prefs = context.read<AppPrefs>();

    switch (auth.status) {
      case AuthStatus.unknown:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case AuthStatus.visitor:
        _announceDisabledAccount(auth);
        if (!prefs.onboardingSeen) {
          return OnboardingScreen(
            prefs: prefs,
            onStart: () => _open(const RegisterScreen()),
            onLogin: () => _open(const LoginScreen()),
          );
        }
        return const VisitorHomeScreen();
      case AuthStatus.authenticated:
        // Double authentification : le code est demandé avant l'accueil.
        if (auth.twoFactorRequired) return const ConfirmDeviceScreen();
        return const AppShell();
    }
  }
}
