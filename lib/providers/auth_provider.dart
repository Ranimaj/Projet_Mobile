import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/foundation.dart';

import '../core/utils/auth_failure.dart';
import '../core/utils/validators.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/storage_service.dart';

enum AuthStatus { unknown, visitor, authenticated }

/// État d'authentification global — pilote le routage entre VisitorHomeScreen
/// et HomeScreen, et expose le profil de l'utilisateur connecté.
class AuthProvider extends ChangeNotifier {
  final AuthService _authService;
  final DateTime Function() _now;
  StreamSubscription<User?>? _authSub;

  // Instancié à la demande : FirebaseStorage.instance exige une app Firebase
  // initialisée, ce qui n'est pas le cas dans les tests ni avant `runApp`.
  StorageService? _storage;
  final StorageService? _injectedStorage;
  StorageService get _storageService => _storage ??= _injectedStorage ?? StorageService();

  /// Délai minimal entre deux envois d'email de vérification.
  static const Duration verificationCooldown = Duration(seconds: 60);

  AuthStatus status = AuthStatus.unknown;
  AppUser? currentUser;
  String? errorMessage;
  String? errorCode;
  bool isLoading = false;

  /// Statut Firebase Auth du compte courant (rafraîchi à chaque changement de
  /// session et via [refreshEmailVerification]).
  bool emailVerified = false;
  bool hasPasswordProvider = false;

  /// Numéro (E.164) auquel le dernier code OTP a été envoyé.
  String? otpPhone;

  /// Biométrie utilisable sur cet appareil (voir [checkBiometrics]).
  bool biometricsAvailable = false;

  /// Le bouton « Déverrouiller par biométrie » n'a de sens que s'il y a une
  /// session à rouvrir : biométrie disponible ET session Firebase mémorisée.
  bool get canUnlockWithBiometrics {
    if (!biometricsAvailable) return false;
    try {
      return _authService.hasRestorableSession;
    } catch (_) {
      return false;
    }
  }

  /// Interroge l'appareil une fois (capteur + biométrie enrôlée).
  Future<void> checkBiometrics() async {
    bool available;
    try {
      available = await _authService.canUseBiometrics();
    } catch (_) {
      available = false;
    }
    if (available != biometricsAvailable) {
      biometricsAvailable = available;
      notifyListeners();
    }
  }

  DateTime? _lastVerificationEmailAt;

  AuthProvider({
    AuthService? authService,
    StorageService? storageService,
    DateTime Function()? clock,
  })  : _authService = authService ?? AuthService(),
        _injectedStorage = storageService,
        _now = clock ?? DateTime.now {
    _authSub = _authService.authStateChanges.listen(_onAuthStateChanged);
  }

  Future<void> _onAuthStateChanged(User? firebaseUser) async {
    if (firebaseUser == null) {
      status = AuthStatus.visitor;
      currentUser = null;
      emailVerified = false;
      hasPasswordProvider = false;
    } else {
      _syncAccountFlags(firebaseUser);
      try {
        currentUser = await _authService.fetchProfile(firebaseUser.uid) ?? currentUser;
      } on AuthFailure {
        // Profil indisponible (hors-ligne...) : on garde la session ouverte.
      }
      status = AuthStatus.authenticated;
    }
    notifyListeners();
  }

  void _syncAccountFlags(User firebaseUser) {
    emailVerified = firebaseUser.emailVerified;
    hasPasswordProvider =
        firebaseUser.providerData.any((p) => p.providerId == AuthService.passwordProviderId);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  void clearError() {
    if (errorMessage == null) return;
    errorMessage = null;
    errorCode = null;
    notifyListeners();
  }

  // --- Inscription / connexion ---------------------------------------------------

  Future<bool> register({
    required String fullName,
    required String email,
    required String password,
  }) =>
      _run(() async {
        final user = await _authService.registerWithEmail(
          email: email,
          password: password,
          fullName: fullName,
        );
        currentUser = user;
        hasPasswordProvider = true;
        await _authService.sendEmailVerification();
        _lastVerificationEmailAt = _now();
      });

  Future<bool> login(String email, String password) => _run(() async {
        await _authService.signInWithEmail(email, password);
      });

  /// Renvoie `true` aussi quand l'utilisateur ferme la fenêtre Google
  /// (aucune erreur à afficher dans ce cas).
  Future<bool> loginWithGoogle() => _run(() async {
        await _authService.signInWithGoogle();
      });

  /// Rouvre la session Firebase mémorisée après une biométrie réussie.
  Future<bool> loginWithBiometrics() => _run(() async {
        final ok = await _authService.authenticateWithBiometrics();
        if (!ok) throw AuthFailure.fromCode('biometric-denied');
        final user = _authService.currentFirebaseUser;
        if (user == null) throw AuthFailure.fromCode('no-session');
        await _onAuthStateChanged(user);
      });

  Future<void> continueAsVisitor() async {
    status = AuthStatus.visitor;
    notifyListeners();
  }

  Future<bool> sendPasswordReset(String email) =>
      _run(() => _authService.sendPasswordReset(email));

  // --- Vérification email --------------------------------------------------------

  Duration get verificationCooldownLeft {
    final last = _lastVerificationEmailAt;
    if (last == null) return Duration.zero;
    final left = verificationCooldown - _now().difference(last);
    return left.isNegative ? Duration.zero : left;
  }

  bool get canResendVerification => verificationCooldownLeft == Duration.zero;

  Future<bool> resendVerificationEmail() => _run(() async {
        if (!canResendVerification) {
          throw AuthFailure(
            'verification-cooldown',
            'Patientez ${verificationCooldownLeft.inSeconds} s avant un nouvel envoi.',
          );
        }
        await _authService.sendEmailVerification();
        _lastVerificationEmailAt = _now();
      });

  /// Recharge le statut de vérification depuis Firebase. Renvoie `true` si
  /// l'email est maintenant vérifié.
  Future<bool> refreshEmailVerification() async {
    final ok = await _run(() async {
      emailVerified = await _authService.reloadUser();
    });
    return ok && emailVerified;
  }

  // --- Profil ------------------------------------------------------------------------

  Future<bool> updateProfile(AppUser updated) => _run(() async {
        currentUser = await _authService.updateProfile(updated);
      });

  /// Envoie une nouvelle photo de profil puis met à jour le profil. L'ancienne
  /// photo hébergée dans Storage est supprimée (best effort).
  Future<bool> updateAvatar(File file) => _run(() async {
        final user = currentUser;
        if (user == null) throw AuthFailure.fromCode('no-session');
        final previousUrl = user.photoUrl;
        final url = await _storageService.uploadAvatar(file, uid: user.id);
        currentUser = await _authService.updateProfile(user.copyWith(photoUrl: url));
        if (previousUrl != null && previousUrl != url) {
          await _storageService.deleteByUrl(previousUrl);
        }
      });

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      _run(() => _authService.changePassword(
            currentPassword: currentPassword,
            newPassword: newPassword,
          ));

  // --- OTP téléphone -----------------------------------------------------------

  Future<bool> sendPhoneOtp(String phone) => _run(() async {
        otpPhone = await _authService.sendPhoneOtp(phone);
      });

  Future<bool> verifyPhoneOtp(String code) => _run(() async {
        final error = Validators.otp(code);
        if (error != null) throw AuthFailure.fromCode('invalid-verification-code');
        await _authService.verifyPhoneOtp(code);
        currentUser = currentUser?.copyWith(isPhoneVerified: true, phoneNumber: otpPhone);
        otpPhone = null;
      });

  // --- Session / compte ----------------------------------------------------------

  Future<bool> logout() => _run(() async {
        await _authService.signOut();
        currentUser = null;
        status = AuthStatus.visitor;
      });

  /// Supprime le compte. [password] est obligatoire pour un compte email /
  /// mot de passe (ré-authentification) ; les comptes Google se ré-authentifient
  /// via Google.
  Future<bool> deleteAccount({String? password}) => _run(() async {
        await _authService.deleteAccount(password: password);
        currentUser = null;
        status = AuthStatus.visitor;
      });

  Future<Map<String, dynamic>> exportMyData() {
    if (currentUser == null) return Future.value({});
    return _authService.exportUserData(currentUser!.id);
  }

  /// Exécute une action async en gérant loading/erreur de façon uniforme.
  Future<bool> _run(Future<void> Function() action) async {
    if (isLoading) return false; // évite les doubles soumissions
    isLoading = true;
    errorMessage = null;
    errorCode = null;
    notifyListeners();
    try {
      await action();
      return true;
    } catch (e) {
      final failure = AuthFailure.from(e);
      errorMessage = failure.message;
      errorCode = failure.code;
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
