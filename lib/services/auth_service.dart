import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:local_auth/local_auth.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/auth_failure.dart';
import '../core/utils/password_hasher.dart';
import '../core/utils/validators.dart';
import '../models/user_model.dart';
import 'local_store.dart';
import 'storage_service.dart';
import 'two_factor_mailer.dart';

/// Code de double authentification envoyé par email.
class TwoFactorEmailSent {
  /// Adresse du compte, à qui le code a été envoyé.
  final String email;

  /// Délai avant de pouvoir demander un nouveau code (zéro : tout de suite).
  final Duration resendIn;
  final DateTime expiresAt;
  const TwoFactorEmailSent({required this.email, required this.resendIn, required this.expiresAt});
}

/// Réponse à une demande de réinitialisation du mot de passe par email.
/// Identique qu'un compte existe ou non pour [email].
class PasswordResetRequest {
  final String email;

  /// Pas d'email possible (SMTP non configuré, compte de démonstration) :
  /// un administrateur réinitialise le mot de passe.
  final bool byAdmin;

  /// Délai avant de pouvoir demander un nouveau code (zéro : tout de suite).
  final Duration resendIn;
  final DateTime? expiresAt;

  const PasswordResetRequest({required this.email, required this.resendIn, required this.expiresAt})
      : byAdmin = false;

  const PasswordResetRequest.admin(this.email)
      : byAdmin = true,
        resendIn = Duration.zero,
        expiresAt = null;
}

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
/// Sans serveur, il n'y a pas de SMS : les codes de vérification du
/// téléphone sont affichés dans l'app ([demoSmsCode], « SMS simulé ») et un
/// mot de passe oublié est réinitialisé par un admin
/// ([resetPasswordByAdmin]). Avec un SMTP configuré, le code de double
/// authentification ([sendTwoFactorEmail]) et celui du mot de passe oublié
/// ([requestPasswordReset]) partent par email.
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

  /// Délai minimum entre deux codes de double authentification par email.
  static const Duration resendCooldown = Duration(seconds: 30);

  /// Réglage qui garde l'empreinte du code email du compte [uid], son
  /// expiration et les essais ratés (jamais le code lui-même).
  static String twoFactorEmailKey(String uid) => 'auth.two_factor_email.$uid';

  AuthService({
    LocalStore? store,
    LocalAuthentication Function()? localAuthFactory,
    StorageService? storage,
    PasswordHasher? hasher,
    Random? random,
    DateTime Function()? clock,
    TwoFactorMailer? mailer,
  })  : _store = store ?? LocalStore(),
        _localAuthFactory = localAuthFactory ?? LocalAuthentication.new,
        _injectedStorage = storage,
        _hasher = hasher ?? PasswordHasher(),
        _random = random ?? Random.secure(),
        _now = clock ?? DateTime.now,
        _mailer = mailer ?? SmtpTwoFactorMailer();

  final TwoFactorMailer _mailer;
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
        final uid = _store.getValue(sessionKey);
        if (uid != null) await _dropEmailCode(uid);
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

  // --- Double authentification par email ---------------------------------------

  /// Le code de double authentification part par email : SMTP configuré et
  /// compte réel. Les comptes de démonstration (`demo-…`) n'ont pas de vraie
  /// boîte mail et gardent le code affiché dans l'app, comme sans SMTP.
  bool get twoFactorByEmail {
    final account = currentAccount;
    return account != null && _mailer.isConfigured && !account.uid.startsWith('demo-');
  }

  _EmailCode? _readEmailCode(String uid) => _EmailCode.read(_store.getValue(twoFactorEmailKey(uid)));

  Future<void> _writeEmailCode(String uid, _EmailCode? code) =>
      _store.setValue(twoFactorEmailKey(uid), code == null ? null : jsonEncode(code.toMap()));

  /// Envoie un code à 6 chiffres à l'adresse du compte, pendant une
  /// connexion en attente de double authentification.
  ///
  /// Un code encore valide n'est pas renvoyé (réouverture de l'écran,
  /// redémarrage), sauf avec [resend] : le nouveau code remplace alors
  /// l'ancien, au plus une fois toutes les [resendCooldown]. Seule une
  /// empreinte du code est stockée.
  Future<TwoFactorEmailSent> sendTwoFactorEmail({bool resend = false}) => _guard(() async {
        final account = _requireAccount();
        if (!twoFactorPending || !twoFactorByEmail) throw AuthFailure.fromCode('otp-not-sent');
        final now = _now();
        final previous = _readEmailCode(account.uid);
        _throwIfLocked(previous, now);
        if (!resend && previous != null && previous.isLive(now)) {
          return _sentInfo(account.email, previous, now);
        }
        final record = await _issueEmailCode(
          owner: account.uid,
          previous: previous,
          now: now,
          validity: otpValidity,
          write: (c) => _writeEmailCode(account.uid, c),
          send: (code, expiresAt) => _mailer.send(
            to: account.email,
            subject: TwoFactorEmail.subject,
            body: TwoFactorEmail.body(
              code: code,
              name: _profile(account.uid)?.fullName ?? '',
              expiresAt: expiresAt,
              validity: otpValidity,
            ),
          ),
        );
        return _sentInfo(account.email, record, now);
      });

  TwoFactorEmailSent _sentInfo(String email, _EmailCode code, DateTime now) =>
      TwoFactorEmailSent(email: email, resendIn: code.resendWait(now), expiresAt: code.expiresAt!);

  /// Vérifie le code reçu par email et valide la connexion. Après
  /// [maxFailedAttempts] codes faux, le compte est bloqué pendant [lockout].
  Future<void> verifyTwoFactorEmail(String code) => _guard(() async {
        final account = _requireAccount();
        await _checkEmailCode(
          owner: account.uid,
          stored: _readEmailCode(account.uid),
          code: code,
          now: _now(),
          write: (c) => _writeEmailCode(account.uid, c),
        );
        await _writeEmailCode(account.uid, null);
        await _store.setValue(twoFactorPendingKey, null);
      });

  // --- Codes par email (double authentification, mot de passe oublié) ---------

  /// Nouveau code à [Validators.otpLength] chiffres pour [owner]. Respecte
  /// l'attente entre deux codes ([resendCooldown]) et garde les essais ratés
  /// de la fenêtre en cours. L'empreinte est écrite AVANT l'envoi (l'ancien
  /// code ne vaut plus rien) ; si l'envoi échoue, aucun code valide ne reste.
  ///
  /// Sans [send] (adresse sans compte, mot de passe oublié), aucun code n'est
  /// tiré ni envoyé : seule la fenêtre (attente, expiration, essais) existe,
  /// pour répondre exactement comme pour un vrai compte.
  Future<_EmailCode> _issueEmailCode({
    required String owner,
    required _EmailCode? previous,
    required DateTime now,
    required Duration validity,
    required Future<void> Function(_EmailCode? code) write,
    required Future<void> Function(String code, DateTime expiresAt)? send,
  }) async {
    final wait = previous?.resendWait(now) ?? Duration.zero;
    if (wait > Duration.zero) {
      throw AuthFailure('otp-cooldown', 'Patiente ${_ceil(wait, 1)} s avant de demander un nouveau code.');
    }
    final expiresAt = now.add(validity);
    // Redemander un code ne remet pas les essais ratés à zéro.
    final failures = previous?.carriedFailures(now) ?? 0;
    if (send == null) {
      final window = _EmailCode(sentAt: now, expiresAt: expiresAt, failures: failures);
      await write(window);
      return window;
    }

    final code = List.generate(Validators.otpLength, (_) => _random.nextInt(10)).join();
    final salt = base64Encode(List<int>.generate(16, (_) => _random.nextInt(256)));
    final record = _EmailCode(
      salt: salt,
      hash: _EmailCode.digest(owner, code, salt),
      sentAt: now,
      expiresAt: expiresAt,
      failures: failures,
    );
    await write(record);
    try {
      await send(code, expiresAt);
    } catch (_) {
      // Jamais l'erreur d'origine : elle pourrait citer la configuration SMTP.
      await write(record.withoutCode());
      throw AuthFailure.fromCode('email-send-failed');
    }
    return record;
  }

  /// Vérifie [code] contre [stored] : blocage, code demandé, expiration, puis
  /// comparaison en temps constant. Un code faux compte un essai ; au
  /// [maxFailedAttempts]-ième, plus de code et blocage de [lockout]. Ne fait
  /// rien de plus en cas de succès : à l'appelant d'effacer le code.
  Future<void> _checkEmailCode({
    required String owner,
    required _EmailCode? stored,
    required String code,
    required DateTime now,
    required Future<void> Function(_EmailCode? code) write,
  }) async {
    _throwIfLocked(stored, now);
    if (stored == null || stored.sentAt == null) throw AuthFailure.fromCode('otp-not-sent');
    if (!stored.expiresAt!.isAfter(now)) {
      await write(stored.withoutCode());
      throw AuthFailure.fromCode('session-expired');
    }
    if (Validators.otp(code) != null || !stored.matches(owner, code.trim())) {
      final failures = stored.failures + 1;
      if (failures >= maxFailedAttempts) {
        final until = now.add(lockout);
        await write(stored.withoutCode(failures: failures, lockedUntil: until));
        throw _lockedFailure(until, now);
      }
      await write(stored.copyWith(failures: failures));
      final left = maxFailedAttempts - failures;
      throw AuthFailure(
        'invalid-verification-code',
        left == 1
            ? 'Code incorrect. Dernier essai avant un blocage de ${lockout.inMinutes} minutes.'
            : 'Code incorrect. Encore $left essais.',
      );
    }
  }

  // --- Mot de passe oublié par email ---------------------------------------------

  /// Validité d'un code de réinitialisation du mot de passe.
  static const Duration passwordResetValidity = Duration(minutes: 10);

  /// Réglage qui garde l'empreinte du code de réinitialisation du compte
  /// [uid] (jamais le code lui-même).
  static String passwordResetKey(String uid) => 'auth.password_reset.$uid';

  /// Fenêtres des adresses sans compte, en mémoire seulement : mêmes
  /// réponses (attente, essais, blocage) que pour un vrai compte.
  final Map<String, _EmailCode> _unknownResets = {};

  /// La réinitialisation par email est possible (SMTP configuré). Sinon, un
  /// admin réinitialise le mot de passe ([resetPasswordByAdmin]).
  bool get passwordResetByEmail => _mailer.isConfigured;

  /// Compte réel (pas `demo-…`) de [email], ou null.
  StoredDoc? _resettableAccount(String email) {
    final account = _accountByEmail(email);
    return account == null || account.id.startsWith('demo-') ? null : account;
  }

  _EmailCode? _readReset(String email, StoredDoc? account) => account == null
      ? _unknownResets[email]
      : _EmailCode.read(_store.getValue(passwordResetKey(account.id)));

  Future<void> _writeReset(String email, StoredDoc? account, _EmailCode? code) async {
    if (account == null) {
      code == null ? _unknownResets.remove(email) : _unknownResets[email] = code;
      return;
    }
    await _store.setValue(passwordResetKey(account.id), code == null ? null : jsonEncode(code.toMap()));
  }

  /// Mot de passe oublié : envoie un code à 6 chiffres à [email] s'il
  /// correspond à un compte réel. La réponse est la même que l'adresse ait un
  /// compte ou non (seul un échec d'envoi la distingue, pour proposer de
  /// réessayer).
  ///
  /// Un compte de démonstration n'a pas de vraie boîte mail : la réponse
  /// indique alors [PasswordResetRequest.byAdmin]. Un code encore valide
  /// n'est pas renvoyé, sauf avec [resend] (au plus une fois toutes les
  /// [resendCooldown]).
  Future<PasswordResetRequest> requestPasswordReset(String email, {bool resend = false}) => _guard(() async {
        final cleanEmail = Validators.normalizeEmail(email);
        if (Validators.email(cleanEmail) != null) throw AuthFailure.fromCode('invalid-email');
        if (!passwordResetByEmail) return PasswordResetRequest.admin(cleanEmail);
        final stored = _accountByEmail(cleanEmail);
        if (stored != null && stored.id.startsWith('demo-')) return PasswordResetRequest.admin(cleanEmail);

        final now = _now();
        _unknownResets.removeWhere((_, c) => !(c.lockedUntil?.isAfter(now) ?? false) && !c.isWindowOpen(now));
        final account = _resettableAccount(cleanEmail);
        final previous = _readReset(cleanEmail, account);
        _throwIfLocked(previous, now);
        if (!resend && previous != null && previous.isWindowOpen(now)) {
          return PasswordResetRequest(email: cleanEmail, resendIn: previous.resendWait(now), expiresAt: previous.expiresAt);
        }
        final record = await _issueEmailCode(
          owner: _resetOwner(account?.id),
          previous: previous,
          now: now,
          validity: passwordResetValidity,
          write: (c) => _writeReset(cleanEmail, account, c),
          send: account == null
              ? null
              : (code, expiresAt) => _mailer.send(
                    to: cleanEmail,
                    subject: PasswordResetEmail.subject,
                    body: PasswordResetEmail.body(
                      code: code,
                      name: _profile(account.id)?.fullName ?? '',
                      expiresAt: expiresAt,
                      validity: passwordResetValidity,
                    ),
                  ),
        );
        return PasswordResetRequest(email: cleanEmail, resendIn: record.resendWait(now), expiresAt: record.expiresAt);
      });

  /// Empreinte propre à la réinitialisation : un code de double
  /// authentification ne peut pas servir ici.
  static String _resetOwner(String? uid) => 'password-reset:${uid ?? ''}';

  /// Change le mot de passe du compte de [email] avec le code reçu. Le
  /// nouveau mot de passe suit les règles de l'inscription ; il est vérifié
  /// avant le code (une faute de saisie ne coûte pas d'essai). Le code est
  /// effacé une fois utilisé.
  Future<void> resetPasswordWithEmailCode({
    required String email,
    required String code,
    required String newPassword,
  }) =>
      _guard(() async {
        if (Validators.newPassword(newPassword) != null) throw AuthFailure.fromCode('weak-password');
        final cleanEmail = Validators.normalizeEmail(email);
        final account = _resettableAccount(cleanEmail);
        await _checkEmailCode(
          owner: _resetOwner(account?.id),
          stored: _readReset(cleanEmail, account),
          code: code,
          now: _now(),
          write: (c) => _writeReset(cleanEmail, account, c),
        );
        // Une fenêtre sans compte n'a pas de code : on n'arrive jamais ici.
        if (account == null) throw AuthFailure.fromCode('otp-not-sent');
        await _setPassword(account.id, newPassword);
        await _writeReset(cleanEmail, account, null);
        _failures.remove(cleanEmail); // la connexion repart sans échec récent
      });

  void _throwIfLocked(_EmailCode? code, DateTime now) {
    final until = code?.lockedUntil;
    if (until != null && until.isAfter(now)) throw _lockedFailure(until, now);
  }

  static AuthFailure _lockedFailure(DateTime until, DateTime now) => AuthFailure(
        'otp-locked',
        "Trop d'essais. Nouvel essai possible dans ${_ceil(until.difference(now), 60)} min.",
      );

  /// [d] en unités de [unitSeconds] secondes, arrondi au-dessus.
  static int _ceil(Duration d, int unitSeconds) => (d.inMilliseconds / (unitSeconds * 1000)).ceil();

  /// Déconnexion : le code ne sert plus, mais les essais ratés et un blocage
  /// restent (se reconnecter ne redonne pas d'essais).
  Future<void> _dropEmailCode(String uid) async {
    final code = _readEmailCode(uid);
    if (code == null) return;
    final keep = code.failures > 0 || code.lockedUntil != null;
    await _writeEmailCode(uid, keep ? code.withoutCode() : null);
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
        await _writeEmailCode(account.uid, null);
        await _store.setValue(passwordResetKey(account.uid), null);
      });

  /// Rend une valeur stockée sérialisable en JSON (dates en ISO 8601).
  static dynamic jsonSafe(dynamic value) {
    if (value is DateTime) return value.toIso8601String();
    if (value is Map) return {for (final e in value.entries) e.key.toString(): jsonSafe(e.value)};
    if (value is Iterable) return value.map(jsonSafe).toList();
    return value;
  }
}

/// Code email de double authentification tel qu'il est stocké : une
/// empreinte salée (HMAC-SHA256), jamais le code lui-même, avec son
/// expiration, les essais ratés et un éventuel blocage.
class _EmailCode {
  final String? salt;
  final String? hash;
  final DateTime? sentAt;
  final DateTime? expiresAt;
  final int failures;
  final DateTime? lockedUntil;

  const _EmailCode({this.salt, this.hash, this.sentAt, this.expiresAt, this.failures = 0, this.lockedUntil});

  bool get hasCode => salt != null && hash != null && expiresAt != null;

  bool isLive(DateTime now) => hasCode && expiresAt!.isAfter(now);

  /// Un code a été demandé et n'a pas expiré (avec ou sans code réel : voir
  /// AuthService._issueEmailCode).
  bool isWindowOpen(DateTime now) => sentAt != null && expiresAt != null && expiresAt!.isAfter(now);

  Duration resendWait(DateTime now) {
    final sent = sentAt;
    if (sent == null) return Duration.zero;
    final wait = sent.add(AuthService.resendCooldown).difference(now);
    return wait.isNegative ? Duration.zero : wait;
  }

  /// Essais ratés repris par le code suivant : ceux de la fenêtre de
  /// validité en cours, remis à zéro après un blocage écoulé.
  int carriedFailures(DateTime now) =>
      lockedUntil == null && expiresAt != null && expiresAt!.isAfter(now) ? failures : 0;

  static String digest(String uid, String code, String salt) =>
      base64Encode(Hmac(sha256, base64Decode(salt)).convert(utf8.encode('$uid:$code')).bytes);

  /// Comparaison en temps constant.
  bool matches(String uid, String code) {
    if (hash == null || salt == null) return false; // fenêtre sans code
    final expected = base64Decode(hash!);
    final actual = base64Decode(digest(uid, code, salt!));
    if (actual.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual[i] ^ expected[i];
    }
    return diff == 0;
  }

  /// Plus de code valide, mais les essais ratés et le blocage restent.
  _EmailCode withoutCode({int? failures, DateTime? lockedUntil}) => _EmailCode(
        expiresAt: expiresAt,
        failures: failures ?? this.failures,
        lockedUntil: lockedUntil ?? this.lockedUntil,
      );

  _EmailCode copyWith({required int failures}) => _EmailCode(
        salt: salt,
        hash: hash,
        sentAt: sentAt,
        expiresAt: expiresAt,
        failures: failures,
        lockedUntil: lockedUntil,
      );

  Map<String, dynamic> toMap() => {
        'salt': salt,
        'hash': hash,
        'sentAt': sentAt?.toIso8601String(),
        'expiresAt': expiresAt?.toIso8601String(),
        'failures': failures,
        'lockedUntil': lockedUntil?.toIso8601String(),
      };

  /// Valeur illisible : traitée comme absente.
  static _EmailCode? read(String? raw) {
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      DateTime? date(String key) => m[key] == null ? null : DateTime.parse(m[key] as String);
      return _EmailCode(
        salt: m['salt'] as String?,
        hash: m['hash'] as String?,
        sentAt: date('sentAt'),
        expiresAt: date('expiresAt'),
        failures: (m['failures'] as num?)?.toInt() ?? 0,
        lockedUntil: date('lockedUntil'),
      );
    } catch (_) {
      return null;
    }
  }
}
