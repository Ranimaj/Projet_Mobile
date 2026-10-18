import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/connectivity_provider.dart';
import 'providers/article_provider.dart';
import 'providers/annonce_provider.dart';
import 'providers/event_provider.dart';
import 'providers/job_provider.dart';
import 'services/notification_service.dart';
import 'screens/visitor/visitor_home_screen.dart';
import 'screens/home/app_shell.dart';
import 'firebase_options.dart';

/// Lance l'app contre les émulateurs Firebase locaux (mode hors-ligne) :
/// `flutter run --dart-define=USE_EMULATOR=true`
const bool _useEmulator = bool.fromEnvironment('USE_EMULATOR');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (_useEmulator) {
    // L'émulateur Android voit la machine hôte via 10.0.2.2.
    final host = defaultTargetPlatform == TargetPlatform.android ? '10.0.2.2' : 'localhost';
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8085);
    await FirebaseStorage.instance.useStorageEmulator(host, 9199);
  }

  // Initialise Hive et ouvre toutes les boîtes utilisées pour le cache
  // local et la file d'attente hors-ligne (BNF3).
  await Hive.initFlutter();
  await Future.wait([
    Hive.openBox(AppConstants.hiveArticlesBox),
    Hive.openBox(AppConstants.hiveAnnoncesBox),
    Hive.openBox(AppConstants.hiveEventsBox),
    Hive.openBox(AppConstants.hiveJobsBox),
    Hive.openBox('applications_box'),
    Hive.openBox(AppConstants.hiveUserBox),
    Hive.openBox(AppConstants.hiveOfflineQueueBox),
    Hive.openBox(AppConstants.hivePrefsBox),
  ]);

  await NotificationService().initialize();

  runApp(const CampusConnectApp());
}

class CampusConnectApp extends StatelessWidget {
  const CampusConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
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
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const _RootRouter(),
      ),
    );
  }
}

/// Bascule entre l'écran Visiteur et l'app connectée selon [AuthProvider].
class _RootRouter extends StatelessWidget {
  const _RootRouter();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    switch (auth.status) {
      case AuthStatus.unknown:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case AuthStatus.visitor:
        return const VisitorHomeScreen();
      case AuthStatus.authenticated:
        return const AppShell();
    }
  }
}
