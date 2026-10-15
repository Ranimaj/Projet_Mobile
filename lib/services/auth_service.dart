import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:local_auth/local_auth.dart';
import '../core/constants/app_constants.dart';
import '../models/user_model.dart';

/// Gestion des Utilisateurs — authentification, inscription, biométrie.
/// Couvre BF1/BF2 et les fonctionnalités avancées "Google Sign-In" et
/// "Authentification biométrique".
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final LocalAuthentication _localAuth = LocalAuthentication();

  User? get currentFirebaseUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Inscription par email académique (BF1). Crée aussi le profil Firestore.
  Future<AppUser> registerWithEmail({
    required String email,
    required String password,
    required String fullName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    final uid = credential.user!.uid;

    final newUser = AppUser(
      id: uid,
      fullName: fullName,
      email: email,
      createdAt: DateTime.now(),
    );
    await _firestore.collection(AppConstants.usersCollection).doc(uid).set(newUser.toMap());
    await credential.user!.updateDisplayName(fullName);
    return newUser;
  }

  /// Connexion email / mot de passe (BF2).
  Future<UserCredential> signInWithEmail(String email, String password) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  /// Connexion via Google Sign-In (fonctionnalité avancée du module Auth).
  Future<UserCredential?> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null; // annulé par l'utilisateur

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final userCredential = await _auth.signInWithCredential(credential);

    // Crée le profil Firestore s'il n'existe pas encore.
    final doc = _firestore.collection(AppConstants.usersCollection).doc(userCredential.user!.uid);
    final snapshot = await doc.get();
    if (!snapshot.exists) {
      await doc.set(AppUser(
        id: userCredential.user!.uid,
        fullName: userCredential.user!.displayName ?? 'Étudiant',
        email: userCredential.user!.email ?? '',
        photoUrl: userCredential.user!.photoURL,
        createdAt: DateTime.now(),
      ).toMap());
    }
    return userCredential;
  }

  /// Authentification biométrique (empreinte / Face ID) — fonctionnalité
  /// avancée utilisée pour déverrouiller rapidement une session déjà ouverte.
  Future<bool> authenticateWithBiometrics() async {
    final canCheck = await _localAuth.canCheckBiometrics;
    final isSupported = await _localAuth.isDeviceSupported();
    if (!canCheck || !isSupported) return false;

    return _localAuth.authenticate(
      localizedReason: 'Authentifiez-vous pour accéder à CampusConnect',
      options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
    );
  }

  Future<void> sendPasswordReset(String email) {
    return _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> sendEmailVerification() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  /// Export RGPD des données personnelles avant suppression du compte (BNF2).
  Future<Map<String, dynamic>> exportUserData(String uid) async {
    final doc = await _firestore.collection(AppConstants.usersCollection).doc(uid).get();
    return doc.data() ?? {};
  }

  Future<void> deleteAccount() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _firestore.collection(AppConstants.usersCollection).doc(uid).delete();
    await _auth.currentUser?.delete();
  }
}
