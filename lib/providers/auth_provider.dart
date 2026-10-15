import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_constants.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

enum AuthStatus { unknown, visitor, authenticated }

/// État d'authentification global — pilote le routage entre VisitorHomeScreen
/// et HomeScreen, et expose le profil de l'utilisateur connecté.
class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  AuthStatus status = AuthStatus.unknown;
  AppUser? currentUser;
  String? errorMessage;
  bool isLoading = false;

  AuthProvider() {
    _authService.authStateChanges.listen((firebaseUser) async {
      if (firebaseUser == null) {
        status = AuthStatus.visitor;
        currentUser = null;
      } else {
        await _loadProfile(firebaseUser.uid);
        status = AuthStatus.authenticated;
      }
      notifyListeners();
    });
  }

  Future<void> _loadProfile(String uid) async {
    final doc = await _firestore.collection(AppConstants.usersCollection).doc(uid).get();
    if (doc.exists) {
      currentUser = AppUser.fromMap(doc.id, doc.data()!);
    }
  }

  Future<bool> register({
    required String fullName,
    required String email,
    required String password,
  }) => _run(() async {
        final user = await _authService.registerWithEmail(
          email: email,
          password: password,
          fullName: fullName,
        );
        currentUser = user;
        await _authService.sendEmailVerification();
      });

  Future<bool> login(String email, String password) => _run(() async {
        await _authService.signInWithEmail(email, password);
      });

  Future<bool> loginWithGoogle() => _run(() async {
        await _authService.signInWithGoogle();
      });

  Future<bool> loginWithBiometrics() => _run(() async {
        final ok = await _authService.authenticateWithBiometrics();
        if (!ok) throw Exception('Authentification biométrique refusée');
      });

  Future<void> continueAsVisitor() async {
    status = AuthStatus.visitor;
    notifyListeners();
  }

  Future<bool> updateProfile(AppUser updated) => _run(() async {
        await _firestore
            .collection(AppConstants.usersCollection)
            .doc(updated.id)
            .set(updated.toMap(), SetOptions(merge: true));
        currentUser = updated;
      });

  Future<bool> sendPasswordReset(String email) => _run(() => _authService.sendPasswordReset(email));

  Future<bool> logout() => _run(() async {
        await _authService.signOut();
        currentUser = null;
        status = AuthStatus.visitor;
      });

  Future<bool> deleteAccount() => _run(() => _authService.deleteAccount());

  Future<Map<String, dynamic>> exportMyData() {
    if (currentUser == null) return Future.value({});
    return _authService.exportUserData(currentUser!.id);
  }

  /// Exécute une action async en gérant loading/erreur de façon uniforme.
  Future<bool> _run(Future<void> Function() action) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await action();
      isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = _friendlyError(e);
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('email-already-in-use')) return 'Cet email est déjà utilisé.';
    if (msg.contains('wrong-password') || msg.contains('invalid-credential')) {
      return 'Email ou mot de passe incorrect.';
    }
    if (msg.contains('user-not-found')) return 'Aucun compte avec cet email.';
    if (msg.contains('weak-password')) return 'Mot de passe trop faible (6 caractères min.).';
    if (msg.contains('network')) return 'Pas de connexion réseau.';
    return 'Une erreur est survenue. Réessayez.';
  }
}
