// Fichier généré normalement par la CLI FlutterFire :
//   dart pub global activate flutterfire_cli
//   flutterfire configure
//
// Ce fichier PLACEHOLDER doit être remplacé par celui généré pour votre
// propre projet Firebase (voir README.md, section "Configuration Firebase").
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions ne sont pas configurées pour cette plateforme. '
          'Lancez `flutterfire configure` à la racine du projet.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'REMPLACER_AVEC_VOTRE_CLE_API',
    appId: 'REMPLACER_AVEC_VOTRE_APP_ID',
    messagingSenderId: 'REMPLACER',
    projectId: 'campusconnect-esprit',
    authDomain: 'campusconnect-esprit.firebaseapp.com',
    storageBucket: 'campusconnect-esprit.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCmvj0V1Od5ZJ3ccBeTfkGgqv4KZa8JuJU',
    appId: '1:902907130330:android:34b560026e5e49a0a390e3',
    messagingSenderId: '902907130330',
    projectId: 'campusconnect-esprit',
    storageBucket: 'campusconnect-esprit.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAT3qkqbRlFA7tKBIjHTnJDGBoOSqtbJxw',
    appId: '1:902907130330:ios:52fbb1b816426dd6a390e3',
    messagingSenderId: '902907130330',
    projectId: 'campusconnect-esprit',
    storageBucket: 'campusconnect-esprit.firebasestorage.app',
    iosBundleId: 'com.esprit.campusconnect',
  );
}
