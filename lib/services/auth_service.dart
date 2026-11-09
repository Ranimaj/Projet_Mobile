import 'dart:async';
import 'dart:math';

import 'package:local_auth/local_auth.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/auth_failure.dart';
import '../core/utils/password_hasher.dart';
import '../core/utils/validators.dart';
import '../models/user_model.dart';
import 'local_store.dart';
import 'storage_service.dart';

/// Compte connecté sur ce téléphone.
class AuthAccount {
  final String uid;
  final String email;
  const AuthAccount({required this.uid, required this.email});

  @override
  bool operator ==(Object other) => other is AuthAccount && other.uid == uid && other.email == email;

  @override
  int get hashCode => Object.hash(uid, email);
}

/// Gestion des Utilisateurs — comptes, connexion, téléphone, biométrie,
/// profil et cycle de vie du compte, **entièrement sur le téléphone**
/// (SQLite via [LocalStore], pas de serveur).
///
/// - `accounts/{uid}` : email et empreinte du mot de passe (PBKDF2, voir
///   [PasswordHasher]) ; jamais le mot de passe lui-même ;
/// - `users/{uid}` : le profil ([AppUser]) ;
/// - la session ouverte est mémorisée dans les réglages ([sessionKey]) et
///   survit au redémarrage de l'app.
///
/// Sans serveur, il n'y a ni email ni SMS : les codes de vérification du
/// téléphone sont affichés dans l'app ([demoSmsCode], « SMS simulé ») et un
/// mot de passe oublié est réinitialisé par un admin
/// ([resetPasswordByAdmin]).
///
/// Toutes les méthodes lèvent une [AuthFailure] avec un message prêt à
/// afficher.
class AuthService {
  static const String accountsCollection = 'accounts';
  static const String sessionKey = 'auth.session_uid';

  /// Connexion ouverte mais double authentification pas encore validée.
  static const String twoFactorPendingKey = 'auth.two_factor_pending';

  static const Duration otpValidity = Duration(minutes: 5);
  static const int maxFailedAttempts = 5;
  static const Duration lockout = Duration(minutes: 5);

  AuthService({
    LocalStore? store,
    LocalAuthentication Function()? localAuthFactory,
    StorageService? storage,
    PasswordHasher? hasher,
    Random? random,
    DateTime Function()? clock,
  })  : _store = store ?? LocalStore(),
        _localAuthFactory = localAuthFactory ?? LocalAuthentication.new,
        _injectedStorage = storage,
        _hasher = hasher ?? PasswordHasher(),
        _random = random ?? Random.secure(),
        _now = clock ?? DateTime.now;

  final LocalStore _store;
  final LocalAuthentication Function() _localAuthFactory;
  final StorageService? _injectedStorage;
  final PasswordHasher _hasher;
  final Random _random;
  final DateTime Function() _now;

  LocalAuthentication? _localAuth;
  LocalAuthentication get _localAuthentication => _localAuth ??= _localAuthFactory();
  StorageService? _storage;
  StorageService get _files => _storage ??= _injectedStorage ?? StorageService();

  final StreamController<AuthAccount?> _changes = StreamController<AuthAccount?>.broadcast();

  /// email → échecs récents (anti force brute, en mémoire).
  final Map<String, List<DateTime>> _failures = {};

  String? _pendingPhone;
  String? _pendingCode;
  DateTime? _codeSentAt;

  /// Lance [action] et convertit toute exception en [AuthFailure].
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      throw AuthFailure.from(e);
    }
  }

  // --- Session -----------------------------------------------------------------

  /// Le compte de la session ouverte sur ce téléphone, ou null.
  AuthAccount? get currentAccount {
    final uid = _store.getValue(sessionKey);
    if (uid == null) return null;
    final account = _store.get(accountsCollection, uid);
    if (account == null) return null;
    return AuthAccount(uid: uid, email: account['email'] as String? ?? '');
  }

  /// La session actuelle dès l'écoute, puis chaque connexion / déconnexion.
  Stream<AuthAccount?> get authStateChanges {
    late StreamController<AuthAccount?> controller;
    StreamSubscription<AuthAccount?>? sub;
    controller = StreamController<AuthAccount?>(
      onListen: () {
        controller.add(currentAccount);
        sub = _changes.stream.listen(controller.add);
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  /// Une session est mémorisée (déverrouillage biométrique possible).
  bool get hasRestorableSession => currentAccount != null;

  /// La connexion attend le code de double authentification.
  bool get twoFactorPending => _store.getValue(twoFactorPendingKey) == '1';

  Future<void> _openSession(String uid, {bool twoFactor = false}) async {
    await _store.setValue(twoFactorPendingKey, twoFactor ? '1' : null);
    await _store.setValue(sessionKey, uid);
    await _store.merge(accountsCollection, uid, {'lastSignInAt': _now()});
    _changes.add(currentAccount);
  }

  Future<void> signOut() => _guard(() async {
        _clearOtp();
        await _store.setValue(sessionKey, null);
        await _store.setValue(twoFactorPendingKey, null);
        _changes.add(null);
      });

  AuthAccount _requireAccount() {
    final account = currentAccount;
    if (account == null) throw AuthFailure.fromCode('no-session');
    return account;
  }

  // --- Profil ----------------------------------------------------------------

  Future<AppUser?> fetchProfile(String uid) => _guard(() async => _profile(uid));

  AppUser? _profile(String uid) {
    final data = _store.get(AppConstants.usersCollection, uid);
    return data == null ? null : AppUser.fromMap(uid, data);
  }

  /// Profil en temps réel (décision d'un admin, désactivation du compte...).
  /// Émet `null` tant que le profil n'existe pas.
  Stream<AppUser?> watchProfile(String uid) => _store
      .watchDoc(AppConstants.usersCollection, uid)
      .map((data) => data == null ? null : AppUser.fromMap(uid, data));

  /// Écriture complète du profil (création).
  Future<void> saveProfile(AppUser user) =>
      _guard(() => _store.merge(AppConstants.usersCollection, user.id, user.toMap()));

  /// Met à jour les champs modifiables du profil ([AppUser.editableFields]).
  /// Renvoie le profil tel qu'il a été enregistré (nom normalisé).
  Future<AppUser> updateProfile(AppUser user) => _guard(() async {
        final nameError = Validators.fullName(user.fullName);
        if (nameError != null) throw AuthFailure('invalid-name', nameError);

        final cleaned = user.copyWith(
          fullName: Validators.normalizeFullName(user.fullName),
          major: user.major?.trim(),
          year: user.year?.trim(),
          skills: user.skills.map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
        );
        final data = {
          // null efface le champ (ex. photo retirée)
          for (final f in AppUser.editableFields) f: null,
          ...cleaned.toEditableMap(),
          'updatedAt': _now(),
        };
        await _store.update(AppConstants.usersCollection, cleaned.id, data);
        return cleaned;
      });

  // --- Email / mot de passe ---------------------------------------------------

  StoredDoc? _accountByEmail(String email) =>
      _store.firstWhere(accountsCollection, (d) => d['email'] == email);

  /// Inscription (BF1) : crée le compte et son profil, puis ouvre la session.
  Future<AppUser> registerWithEmail({
    required String email,
    required String password,
    required String fullName,
  }) =>
      _guard(() async {
        final cleanEmail = Validators.normalizeEmail(email);
        final cleanName = Validators.normalizeFullName(fullName);
        if (Validators.email(cleanEmail) != null) throw AuthFailure.fromCode('invalid-email');
        if (Validators.newPassword(password) != null) throw AuthFailure.fromCode('weak-password');
        if (_accountByEmail(cleanEmail) != null) throw AuthFailure.fromCode('email-already-in-use');

        final uid = LocalStore.newId();
        final now = _now();
        await _store.set(accountsCollection, uid, {
          'email': cleanEmail,
          'password': _hasher.hash(password).toMap(),
          'createdAt': now,
        });
        final newUser = AppUser(id: uid, fullName: cleanName, email: cleanEmail, createdAt: now);
        await _store.set(AppConstants.usersCollection, uid, newUser.toMap());
        await _openSession(uid);
        return newUser;
      });

  /// Connexion email / mot de passe (BF2). Avec la double authentification,
  /// la session s'ouvre en attente du code ([twoFactorPending]).
  Future<AuthAccount> signInWithEmail(String email, String password) => _guard(() async {
        final cleanEmail = Validators.normalizeEmail(email);
        _checkLockout(cleanEmail);
        final account = _accountByEmail(cleanEmail);
        final hash = PasswordHash.fromMap(_mapOf(account?.data['password']));
        if (account == null || hash == null || !PasswordHasher.verify(password, hash)) {
          _recordFailure(cleanEmail);
          throw AuthFailure.fromCode('invalid-credential');
        }
        _failures.remove(cleanEmail);
        final profile = _profile(account.id);
        if (profile?.disabled == true) throw AuthFailure.fromCode('user-disabled');
        await _openSession(account.id, twoFactor: _twoFactorActive(profile));
        return currentAccount!;
      });

  /// La double authentification ne s'applique qu'avec un numéro vérifié.
  static bool _twoFactorActive(AppUser? user) =>
      user != null && user.twoFactorEnabled && user.isPhoneVerified && (user.phoneNumber ?? '').isNotEmpty;

  void _checkLockout(String email) {
    final since = _now().subtract(lockout);
    final recent = (_failures[email] ?? const <DateTime>[]).where((t) => t.isAfter(since)).toList();
    _failures[email] = recent;
    if (recent.length >= maxFailedAttempts) throw AuthFailure.fromCode('too-many-requests');
  }

  void _recordFailure(String email) => (_failures[email] ??= []).add(_now());

  static Map<String, dynamic>? _mapOf(Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;

  /// Vérifie le mot de passe du compte connecté (opérations sensibles).
  Future<void> reauthenticateWithPassword(String password) => _guard(() async {
        final account = _requireAccount();
        if (password.isEmpty) throw AuthFailure.fromCode('password-required');
        final hash = PasswordHash.fromMap(_mapOf(_store.get(accountsCollection, account.uid)?['password']));
        if (hash == null || !PasswordHasher.verify(password, hash)) {
          throw AuthFailure.fromCode('wrong-password');
        }
      });

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      _guard(() async {
        if (Validators.newPassword(newPassword) != null) throw AuthFailure.fromCode('weak-password');
        if (currentPassword == newPassword) throw AuthFailure.fromCode('same-password');
        await reauthenticateWithPassword(currentPassword);
        await _setPassword(_requireAccount().uid, newPassword);
      });

  Future<void> _setPassword(String uid, String password) =>
      _store.update(accountsCollection, uid, {'password': _hasher.hash(password).toMap()});

  /// Mot de passe oublié : un admin attribue un mot de passe provisoire au
  /// compte [uid] et le transmet à l'étudiant. Renvoie ce mot de passe.
  Future<String> resetPasswordByAdmin(String uid) => _guard(() async {
        if (!_store.exists(accountsCollection, uid)) throw AuthFailure.fromCode('user-not-found');
        const letters = 'abcdefghjkmnpqrstuvwxyz';
        final word = List.generate(6, (_) => letters[_random.nextInt(letters.length)]).join();
        final temporary = 'Campus-$word${10 + _random.nextInt(90)}';
        await _setPassword(uid, temporary);
        return temporary;
      });

  // --- Biométrie ---------------------------------------------------------------

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

  // --- Code téléphone (SMS simulé) ----------------------------------------------

  /// Code du dernier « SMS » : sans serveur, l'app l'affiche elle-même.
  String? get demoSmsCode => _pendingCode;

  /// Prépare un code pour [phone] (saisie libre, normalisée en E.164) et
  /// renvoie le numéro normalisé. Rappeler la méthode envoie un nouveau code.
  Future<String> sendPhoneOtp(String phone) => _guard(() async {
        final account = _requireAccount();
        final normalized = Validators.normalizePhone(phone);
        if (normalized == null) throw AuthFailure.fromCode('invalid-phone-number');
        final taken = _store.firstWhere(
          AppConstants.usersCollection,
          (d) => d['phoneNumber'] == normalized && d['isPhoneVerified'] == true,
        );
        if (taken != null && taken.id != account.uid) throw AuthFailure.fromCode('credential-already-in-use');
        _pendingPhone = normalized;
        _pendingCode = List.generate(6, (_) => _random.nextInt(10)).join();
        _codeSentAt = _now();
        return normalized;
      });

  /// Vérifie le code : le numéro devient vérifié sur le profil, et une
  /// double authentification en attente est validée.
  Future<void> verifyPhoneOtp(String code) => _guard(() async {
        final account = _requireAccount();
        final phone = _pendingPhone;
        final expected = _pendingCode;
        final sentAt = _codeSentAt;
        if (phone == null || expected == null || sentAt == null) throw AuthFailure.fromCode('otp-not-sent');
        if (_now().difference(sentAt) > otpValidity) {
          _clearOtp();
          throw AuthFailure.fromCode('session-expired');
        }
        if (Validators.otp(code) != null || code.trim() != expected) {
          throw AuthFailure.fromCode('invalid-verification-code');
        }
        await _store.update(AppConstants.usersCollection, account.uid, {
          'isPhoneVerified': true,
          'phoneNumber': phone,
          'updatedAt': _now(),
        });
        await _store.setValue(twoFactorPendingKey, null);
        _clearOtp();
      });

  void _clearOtp() {
    _pendingPhone = null;
    _pendingCode = null;
    _codeSentAt = null;
  }

  // --- Compte ------------------------------------------------------------------

  /// Export RGPD des données personnelles (BNF2), sérialisable en JSON.
  Future<Map<String, dynamic>> exportUserData(String uid) => _guard(() async {
        final account = _store.get(accountsCollection, uid) ?? const {};
        return {
          'exportedAt': _now().toIso8601String(),
          'account': {
            'uid': uid,
            'email': account['email'],
            'createdAt': parseDate(account['createdAt'])?.toIso8601String(),
            'lastSignInAt': parseDate(account['lastSignInAt'])?.toIso8601String(),
          },
          'profile': jsonSafe(_store.get(AppConstants.usersCollection, uid) ?? const {}),
        };
      });

  /// Supprime le compte, son profil et ses fichiers (photo, carte), après
  /// vérification du mot de passe. [beforeDelete] nettoie les autres données
  /// du compte (appareils, connexions...).
  Future<void> deleteAccount({String? password, Future<void> Function(String uid)? beforeDelete}) =>
      _guard(() async {
        final account = currentAccount;
        if (account == null) return;
        if (password == null || password.isEmpty) throw AuthFailure.fromCode('password-required');
        await reauthenticateWithPassword(password);

        if (beforeDelete != null) await beforeDelete(account.uid);
        final profile = _store.get(AppConstants.usersCollection, account.uid);
        final card = profile?['studentCard'];
        await _files.delete(card is Map ? card['imagePath'] as String? : null);
        await _files.delete(profile?['photoUrl'] as String?);
        await _store.delete(AppConstants.usersCollection, account.uid);
        await _store.delete(accountsCollection, account.uid);
        await signOut();
      });

  /// Rend une valeur stockée sérialisable en JSON (dates en ISO 8601).
  static dynamic jsonSafe(dynamic value) {
    if (value is DateTime) return value.toIso8601String();
    if (value is Map) return {for (final e in value.entries) e.key.toString(): jsonSafe(e.value)};
    if (value is Iterable) return value.map(jsonSafe).toList();
    return value;
  }
}
