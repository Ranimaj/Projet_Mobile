import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:local_auth/local_auth.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/auth_failure.dart';
import '../core/utils/validators.dart';
import '../models/user_model.dart';

/// Gestion des Utilisateurs — authentification, inscription, OTP, biométrie,
/// profil et cycle de vie du compte.
///
/// Toutes les méthodes normalisent leurs entrées (email, nom, téléphone) et
/// lèvent une [AuthFailure] avec un message prêt à afficher. Les dépendances
/// sont injectables pour les tests ; Google Sign-In et la biométrie sont
/// instanciés à la demande (le plugin web plante à la construction si aucun
/// client ID n'est configuré).
class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final GoogleSignIn Function() _googleFactory;
  final LocalAuthentication Function() _localAuthFactory;

  GoogleSignIn? _google;
  LocalAuthentication? _localAuth;

  String? _verificationId;
  int? _resendToken;
  String? _pendingPhone;

  static const String passwordProviderId = 'password';
  static const String googleProviderId = 'google.com';

  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    GoogleSignIn Function()? googleFactory,
    LocalAuthentication Function()? localAuthFactory,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance,
        _googleFactory = googleFactory ?? GoogleSignIn.new,
        _localAuthFactory = localAuthFactory ?? LocalAuthentication.new;

  GoogleSignIn get _googleSignIn => _google ??= _googleFactory();
  LocalAuthentication get _localAuthentication => _localAuth ??= _localAuthFactory();

  User? get currentFirebaseUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();
  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  /// Identifiants des fournisseurs liés au compte courant (`password`,
  /// `google.com`, `phone`...).
  List<String> get providerIds =>
      _auth.currentUser?.providerData.map((p) => p.providerId).toList() ?? const [];

  bool get hasPasswordProvider => providerIds.contains(passwordProviderId);

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _firestore.collection(AppConstants.usersCollection).doc(uid);

  User _requireUser() {
    final user = _auth.currentUser;
    if (user == null) throw AuthFailure.fromCode('no-session');
    return user;
  }

  /// Lance [action] et convertit toute exception en [AuthFailure].
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      throw AuthFailure.from(e);
    }
  }

  // --- Profil ----------------------------------------------------------------

  Future<AppUser?> fetchProfile(String uid) => _guard(() async {
        final doc = await _userDoc(uid).get();
        final data = doc.data();
        return doc.exists && data != null ? AppUser.fromMap(doc.id, data) : null;
      });

  /// Écriture complète du profil (création). Pour une modification par
  /// l'utilisateur, utiliser [updateProfile] qui ne touche qu'aux champs
  /// autorisés.
  Future<void> saveProfile(AppUser user) => _guard(
        () => _userDoc(user.id).set(user.toMap(), SetOptions(merge: true)),
      );

  /// Met à jour les champs modifiables du profil ([AppUser.editableFields])
  /// et synchronise nom / photo avec Firebase Auth. Renvoie le profil tel
  /// qu'il a été enregistré (nom normalisé).
  Future<AppUser> updateProfile(AppUser user) => _guard(() async {
        final nameError = Validators.fullName(user.fullName);
        if (nameError != null) throw AuthFailure('invalid-name', nameError);

        final cleaned = user.copyWith(
          fullName: Validators.normalizeFullName(user.fullName),
          major: user.major?.trim(),
          year: user.year?.trim(),
          skills: user.skills.map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
        );

        final data = cleaned.toEditableMap()..['updatedAt'] = FieldValue.serverTimestamp();
        await _userDoc(cleaned.id).set(data, SetOptions(merge: true));

        final firebaseUser = _auth.currentUser;
        if (firebaseUser != null && firebaseUser.uid == cleaned.id) {
          if (firebaseUser.displayName != cleaned.fullName) {
            await firebaseUser.updateDisplayName(cleaned.fullName);
          }
          if (cleaned.photoUrl != null && firebaseUser.photoURL != cleaned.photoUrl) {
            await firebaseUser.updatePhotoURL(cleaned.photoUrl);
          }
        }
        return cleaned;
      });

  // --- Email / mot de passe ---------------------------------------------------

  /// Inscription par email académique (BF1). Crée aussi le profil Firestore.
  Future<AppUser> registerWithEmail({
    required String email,
    required String password,
    required String fullName,
  }) =>
      _guard(() async {
        final cleanEmail = Validators.normalizeEmail(email);
        final cleanName = Validators.normalizeFullName(fullName);
        final credential = await _auth.createUserWithEmailAndPassword(
          email: cleanEmail,
          password: password,
        );
        final firebaseUser = credential.user!;

        final newUser = AppUser(
          id: firebaseUser.uid,
          fullName: cleanName,
          email: cleanEmail,
          createdAt: DateTime.now(),
        );
        await _userDoc(firebaseUser.uid).set(newUser.toMap());
        await firebaseUser.updateDisplayName(cleanName);
        return newUser;
      });

  /// Connexion email / mot de passe (BF2).
  Future<UserCredential> signInWithEmail(String email, String password) => _guard(
        () => _auth.signInWithEmailAndPassword(
          email: Validators.normalizeEmail(email),
          password: password,
        ),
      );

  Future<void> sendPasswordReset(String email) => _guard(
        () => _auth.sendPasswordResetEmail(email: Validators.normalizeEmail(email)),
      );

  Future<void> sendEmailVerification() => _guard(() async {
        await _auth.currentUser?.sendEmailVerification();
      });

  /// Recharge l'utilisateur Firebase (statut de vérification email, fournisseurs
  /// liés...) et renvoie `true` si l'email est vérifié.
  Future<bool> reloadUser() => _guard(() async {
        final user = _auth.currentUser;
        if (user == null) return false;
        await user.reload();
        return _auth.currentUser?.emailVerified ?? false;
      });

  /// Ré-authentifie l'utilisateur avec son mot de passe — requis par Firebase
  /// avant les opérations sensibles (changement de mot de passe, suppression).
  Future<void> reauthenticateWithPassword(String password) => _guard(() async {
        final user = _requireUser();
        if (!hasPasswordProvider) throw AuthFailure.fromCode('no-password-provider');
        if (password.isEmpty) throw AuthFailure.fromCode('password-required');
        await user.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: user.email!, password: password),
        );
      });

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      _guard(() async {
        final weak = Validators.newPassword(newPassword);
        if (weak != null) throw AuthFailure.fromCode('weak-password');
        if (currentPassword == newPassword) throw AuthFailure.fromCode('same-password');

        await reauthenticateWithPassword(currentPassword);
        await _requireUser().updatePassword(newPassword);
      });

  // --- Google ------------------------------------------------------------------

  /// Connexion via Google Sign-In. Renvoie `null` si l'utilisateur annule.
  Future<UserCredential?> signInWithGoogle() => _guard(() async {
        final credential = await _googleCredential();
        if (credential == null) return null;
        final userCredential = await _auth.signInWithCredential(credential);

        // Crée le profil Firestore s'il n'existe pas encore.
        final user = userCredential.user!;
        final doc = _userDoc(user.uid);
        if (!(await doc.get()).exists) {
          await doc.set(AppUser(
            id: user.uid,
            fullName: user.displayName ?? 'Étudiant',
            email: user.email ?? '',
            photoUrl: user.photoURL,
            createdAt: DateTime.now(),
          ).toMap());
        }
        return userCredential;
      });

  Future<OAuthCredential?> _googleCredential() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;
    final googleAuth = await googleUser.authentication;
    return GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
  }

  // --- Biométrie ---------------------------------------------------------------

  /// `true` quand une session Firebase est encore mémorisée sur l'appareil
  /// (l'utilisateur ne s'est pas déconnecté explicitement).
  bool get hasRestorableSession => _auth.currentUser != null;

  /// L'appareil dispose-t-il d'une biométrie utilisable (capteur + empreinte
  /// ou visage enrôlé) ? Ne lève jamais : `false` en cas de doute.
  Future<bool> canUseBiometrics() async {
    try {
      final local = _localAuthentication;
      if (!await local.isDeviceSupported()) return false;
      if (!await local.canCheckBiometrics) return false;
      return (await local.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Déverrouille rapidement une session déjà ouverte (empreinte / Face ID).
  /// Renvoie `false` si indisponible ou refusée.
  Future<bool> authenticateWithBiometrics() => _guard(() async {
        final local = _localAuthentication;
        final canCheck = await local.canCheckBiometrics;
        final isSupported = await local.isDeviceSupported();
        if (!canCheck || !isSupported) return false;

        return local.authenticate(
          localizedReason: 'Authentifiez-vous pour accéder à CampusConnect',
          options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
        );
      });

  // --- OTP téléphone -----------------------------------------------------------

  /// Envoie un code SMS au [phone] (saisie libre, normalisée en E.164) et
  /// renvoie le numéro normalisé. Appelable à nouveau pour renvoyer le code.
  Future<String> sendPhoneOtp(String phone) => _guard(() async {
        _requireUser();
        final normalized = Validators.normalizePhone(phone);
        if (normalized == null) throw AuthFailure.fromCode('invalid-phone-number');

        final resendToken = normalized == _pendingPhone ? _resendToken : null;
        _pendingPhone = normalized;

        final sent = Completer<void>();
        await _auth.verifyPhoneNumber(
          phoneNumber: normalized,
          forceResendingToken: resendToken,
          timeout: const Duration(seconds: 60),
          verificationCompleted: (credential) async {
            // Validation automatique (Android) : on lie directement le numéro.
            try {
              await _linkPhone(credential, normalized);
              if (!sent.isCompleted) sent.complete();
            } catch (e) {
              if (!sent.isCompleted) sent.completeError(e);
            }
          },
          verificationFailed: (e) {
            if (!sent.isCompleted) sent.completeError(e);
          },
          codeSent: (verificationId, resendToken) {
            _verificationId = verificationId;
            _resendToken = resendToken;
            if (!sent.isCompleted) sent.complete();
          },
          codeAutoRetrievalTimeout: (verificationId) => _verificationId = verificationId,
        );
        await sent.future;
        return normalized;
      });

  /// Vérifie le code saisi et lie le numéro au compte courant.
  Future<void> verifyPhoneOtp(String code) => _guard(() async {
        final verificationId = _verificationId;
        final phone = _pendingPhone;
        if (verificationId == null || phone == null) throw AuthFailure.fromCode('otp-not-sent');
        if (Validators.otp(code) != null) throw AuthFailure.fromCode('invalid-verification-code');

        await _linkPhone(
          PhoneAuthProvider.credential(verificationId: verificationId, smsCode: code.trim()),
          phone,
        );
        _verificationId = null;
        _resendToken = null;
        _pendingPhone = null;
      });

  Future<void> _linkPhone(PhoneAuthCredential credential, String phone) async {
    final user = _requireUser();
    await user.linkWithCredential(credential);
    await _userDoc(user.uid).set({
      'isPhoneVerified': true,
      'phoneNumber': phone,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // --- Session / compte ----------------------------------------------------------

  Future<void> signOut() => _guard(() async {
        // Google n'est pas forcément initialisé : ne pas le construire pour rien.
        if (_google != null) await _google!.signOut();
        await _auth.signOut();
      });

  /// Export RGPD des données personnelles (BNF2) — profil Firestore + données
  /// de compte, sous une forme sérialisable en JSON.
  Future<Map<String, dynamic>> exportUserData(String uid) => _guard(() async {
        final doc = await _userDoc(uid).get();
        final user = _auth.currentUser;
        return {
          'exportedAt': DateTime.now().toIso8601String(),
          'account': {
            'uid': uid,
            'email': user?.email,
            'emailVerified': user?.emailVerified,
            'phoneNumber': user?.phoneNumber,
            'providers': providerIds,
            'createdAt': user?.metadata.creationTime?.toIso8601String(),
            'lastSignInAt': user?.metadata.lastSignInTime?.toIso8601String(),
          },
          'profile': _jsonSafe(doc.data() ?? <String, dynamic>{}),
        };
      });

  /// Supprime le compte et son profil. La ré-authentification est faite
  /// d'abord (mot de passe ou Google) pour éviter l'erreur
  /// `requires-recent-login` en plein milieu ; si la suppression du compte
  /// échoue malgré tout, le profil Firestore est restauré pour ne pas laisser
  /// un compte orphelin.
  Future<void> deleteAccount({String? password}) => _guard(() async {
        final user = _auth.currentUser;
        if (user == null) return;

        if (hasPasswordProvider) {
          if (password == null || password.isEmpty) throw AuthFailure.fromCode('password-required');
          await reauthenticateWithPassword(password);
        } else if (providerIds.contains(googleProviderId)) {
          final credential = await _googleCredential();
          if (credential == null) throw AuthFailure.fromCode('cancelled');
          await user.reauthenticateWithCredential(credential);
        }

        final doc = _userDoc(user.uid);
        final backup = (await doc.get()).data();
        await doc.delete();
        try {
          await user.delete();
        } catch (e) {
          if (backup != null) await doc.set(backup);
          rethrow;
        }
      });

  static dynamic _jsonSafe(dynamic value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is DateTime) return value.toIso8601String();
    if (value is Map) return {for (final e in value.entries) e.key.toString(): _jsonSafe(e.value)};
    if (value is Iterable) return value.map(_jsonSafe).toList();
    return value;
  }
}
