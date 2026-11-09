import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/utils/auth_failure.dart';
import '../core/utils/validators.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/device_session_service.dart';
import '../services/storage_service.dart';
import '../services/student_card_service.dart';

enum AuthStatus { unknown, visitor, authenticated }

/// État d'authentification global — pilote le routage entre VisitorHomeScreen
/// et HomeScreen, et expose le profil de l'utilisateur connecté. Tout est
/// stocké sur le téléphone (voir [AuthService]).
class AuthProvider extends ChangeNotifier {
  final AuthService _authService;
  final DateTime Function() _now;
  StreamSubscription<AuthAccount?>? _authSub;
  StreamSubscription<AppUser?>? _profileSub;
  String? _watchedUid;

  final StorageService? _injectedStorage;
  StorageService? _storage;
  StorageService get _storageService => _storage ??= _injectedStorage ?? StorageService();

  final StudentCardService? _injectedCardService;
  StudentCardService? _cardService;
  StudentCardService get _studentCardService =>
      _cardService ??= _injectedCardService ?? StudentCardService(storage: _storageService);

  /// Code d'erreur posé quand un admin a désactivé le compte.
  static const String accountDisabledCode = 'account-disabled';

  final DeviceSessionService? _injectedSessions;
  DeviceSessionService? _sessions;

  /// Historique des connexions de ce téléphone (« Mes appareils »), ou
  /// `null` si le stockage local n'est pas disponible (tests d'écran).
  DeviceSessionService? get deviceSessions {
    try {
      return _sessions ??= _injectedSessions ?? DeviceSessionService();
    } catch (_) {
      return null;
    }
  }

  /// Double authentification : le mot de passe est bon, l'app attend le code
  /// envoyé au numéro vérifié avant d'ouvrir l'accueil.
  bool twoFactorRequired = false;

  AuthStatus status = AuthStatus.unknown;
  AppUser? currentUser;
  String? errorMessage;
  String? errorCode;
  bool isLoading = false;

  /// Numéro (E.164) auquel le dernier code a été envoyé.
  String? otpPhone;

  /// Code du dernier « SMS » : sans serveur, l'app l'affiche elle-même.
  String? get demoSmsCode => _authService.demoSmsCode;

  /// Biométrie utilisable sur cet appareil (voir [checkBiometrics]).
  bool biometricsAvailable = false;

  /// Le bouton « Déverrouiller par biométrie » n'a de sens que s'il y a une
  /// session à rouvrir : biométrie disponible ET session mémorisée.
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

  AuthProvider({
    AuthService? authService,
    StorageService? storageService,
    StudentCardService? studentCardService,
    DeviceSessionService? deviceSessionService,
    DateTime Function()? clock,
  })  : _authService = authService ?? AuthService(),
        _injectedStorage = storageService,
        _injectedCardService = studentCardService,
        _injectedSessions = deviceSessionService,
        _now = clock ?? DateTime.now {
    _authSub = _authService.authStateChanges.listen(_onAuthStateChanged);
  }

  Future<void> _onAuthStateChanged(AuthAccount? account) async {
    if (account == null) {
      _stopProfileWatch();
      twoFactorRequired = false;
      status = AuthStatus.visitor;
      currentUser = null;
    } else {
      AppUser? profile;
      try {
        profile = await _authService.fetchProfile(account.uid);
      } on AuthFailure {
        // Profil illisible : la session reste ouverte avec le dernier connu.
      }
      if (profile?.disabled == true) {
        await _signOutDisabled();
        return;
      }
      twoFactorRequired = _authService.twoFactorPending;
      currentUser = profile ?? currentUser;
      status = AuthStatus.authenticated;
      _watchProfile(account.uid);
    }
    notifyListeners();
  }

  /// Un admin a désactivé le compte : session fermée, message expliqué.
  Future<void> _signOutDisabled() async {
    _stopProfileWatch();
    try {
      await _authService.signOut();
    } catch (_) {
      // La session sera de toute façon masquée : l'app repasse en visiteur.
    }
    currentUser = null;
    twoFactorRequired = false;
    status = AuthStatus.visitor;
    errorCode = accountDisabledCode;
    errorMessage = "Compte désactivé. Contacte l'administration.";
    notifyListeners();
  }

  /// Écoute le profil tant que la session est ouverte : la décision d'un
  /// admin sur la carte étudiant apparaît en direct et une désactivation
  /// ferme la session immédiatement.
  void _watchProfile(String uid) {
    if (_watchedUid == uid && _profileSub != null) return;
    _stopProfileWatch();
    Stream<AppUser?> stream;
    try {
      stream = _authService.watchProfile(uid);
    } catch (_) {
      return; // stockage indisponible : la lecture ponctuelle suffit.
    }
    _watchedUid = uid;
    _profileSub = stream.listen((profile) {
      if (profile == null || status != AuthStatus.authenticated) return;
      if (profile.id != uid) return;
      if (profile.disabled) {
        _signOutDisabled();
        return;
      }
      currentUser = profile;
      notifyListeners();
    }, onError: (Object _) {});
  }

  void _stopProfileWatch() {
    _profileSub?.cancel();
    _profileSub = null;
    _watchedUid = null;
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _stopProfileWatch();
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
        await _recordLogin(user.id);
      });

  /// Connexion par mot de passe. Avec la double authentification, la session
  /// s'ouvre avec [twoFactorRequired] : l'app demande alors le code.
  Future<bool> login(String email, String password) => _run(() async {
        final account = await _authService.signInWithEmail(email, password);
        await _recordLogin(account.uid);
      });

  Future<void> _recordLogin(String uid) async {
    try {
      await deviceSessions?.recordLogin(uid);
    } catch (_) {
      // L'historique est un plus : il ne bloque jamais la connexion.
    }
  }

  /// Rouvre la session mémorisée après une biométrie réussie.
  Future<bool> loginWithBiometrics() => _run(() async {
        final ok = await _authService.authenticateWithBiometrics();
        if (!ok) throw AuthFailure.fromCode('biometric-denied');
        final account = _authService.currentAccount;
        if (account == null) throw AuthFailure.fromCode('no-session');
        await _onAuthStateChanged(account);
      });

  Future<void> continueAsVisitor() async {
    status = AuthStatus.visitor;
    notifyListeners();
  }

  // --- Profil ------------------------------------------------------------------------

  Future<bool> updateProfile(AppUser updated) => _run(() async {
        currentUser = await _authService.updateProfile(updated);
      });

  /// Enregistre une nouvelle photo de profil puis met à jour le profil.
  /// L'ancienne photo est supprimée du téléphone.
  Future<bool> updateAvatar(File file) => _run(() async {
        final user = currentUser;
        if (user == null) throw AuthFailure.fromCode('no-session');
        final previous = user.photoUrl;
        final path = await _storageService.saveAvatar(file, uid: user.id);
        currentUser = await _authService.updateProfile(user.copyWith(photoUrl: path));
        if (previous != null && previous != path) await _storageService.delete(previous);
      });

  /// Envoie la carte étudiant pour validation par un admin.
  Future<bool> submitStudentCard(File photo) => _run(() async {
        final user = currentUser;
        if (user == null) throw AuthFailure.fromCode('no-session');
        final card = await _studentCardService.submit(uid: user.id, photo: photo, now: _now);
        currentUser = user.copyWith(studentCard: card);
      });

  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      _run(() => _authService.changePassword(
            currentPassword: currentPassword,
            newPassword: newPassword,
          ));

  // --- Code téléphone -----------------------------------------------------------

  Future<bool> sendPhoneOtp(String phone) => _run(() async {
        otpPhone = await _authService.sendPhoneOtp(phone);
      });

  /// Vérifie le code : numéro vérifié, et double authentification validée
  /// si elle était en attente.
  Future<bool> verifyPhoneOtp(String code) => _run(() async {
        final error = Validators.otp(code);
        if (error != null) throw AuthFailure.fromCode('invalid-verification-code');
        await _authService.verifyPhoneOtp(code);
        currentUser = currentUser?.copyWith(isPhoneVerified: true, phoneNumber: otpPhone);
        otpPhone = null;
        twoFactorRequired = false;
      });

  // --- Session / compte ----------------------------------------------------------

  Future<bool> logout() => _run(() async {
        final uid = currentUser?.id;
        if (uid != null) {
          try {
            await deviceSessions?.recordLogout(uid);
          } catch (_) {}
        }
        await _authService.signOut();
        _stopProfileWatch();
        twoFactorRequired = false;
        currentUser = null;
        status = AuthStatus.visitor;
      });

  /// Supprime le compte après vérification du mot de passe, avec son
  /// historique de connexions.
  Future<bool> deleteAccount({String? password}) => _run(() async {
        final sessions = deviceSessions;
        await _authService.deleteAccount(
          password: password,
          beforeDelete: sessions == null
              ? null
              : (uid) async {
                  try {
                    await sessions.deleteAll(uid);
                  } catch (_) {}
                },
        );
        _stopProfileWatch();
        twoFactorRequired = false;
        currentUser = null;
        status = AuthStatus.visitor;
      });

  Future<Map<String, dynamic>> exportMyData() async {
    final user = currentUser;
    if (user == null) return {};
    final data = await _authService.exportUserData(user.id);
    final sessions = deviceSessions;
    if (sessions == null) return data;
    try {
      return {...data, ...await sessions.export(user.id)};
    } catch (_) {
      return data; // l'export du profil reste utile sans l'historique
    }
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
