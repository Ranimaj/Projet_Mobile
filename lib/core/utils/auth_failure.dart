/// Erreur métier du module Auth : message affichable + code technique stable.
class AuthFailure implements Exception {
  final String code;
  final String message;

  /// Exception d'origine, conservée pour le débogage (jamais affichée).
  final Object? cause;

  const AuthFailure(this.code, this.message, {this.cause});

  /// Convertit n'importe quelle exception en [AuthFailure] lisible.
  factory AuthFailure.from(Object error) {
    if (error is AuthFailure) return error;
    return AuthFailure('unknown', 'Une erreur est survenue. Réessayez.', cause: error);
  }

  factory AuthFailure.fromCode(String code, {Object? cause}) {
    final message = _messages[code];
    return AuthFailure(code, message ?? 'Une erreur est survenue. Réessayez.', cause: cause);
  }

  static const Map<String, String> _messages = {
    'email-already-in-use': 'Cet email est déjà utilisé.',
    'invalid-email': 'Adresse email invalide.',
    'wrong-password': 'Mot de passe incorrect.',
    'invalid-credential': 'Email ou mot de passe incorrect.',
    'user-not-found': 'Aucun compte avec cet email.',
    'user-disabled': 'Ce compte a été désactivé.',
    'weak-password': 'Mot de passe trop faible (8 caractères, lettres et chiffres).',
    'too-many-requests': 'Trop de tentatives. Réessayez dans 5 minutes.',
    'invalid-phone-number': 'Numéro de téléphone invalide.',
    'invalid-verification-code': 'Code incorrect. Vérifiez et réessayez.',
    'session-expired': 'Le code a expiré. Demandez-en un nouveau.',
    'credential-already-in-use': 'Ce numéro est déjà associé à un autre compte.',
    'cancelled': 'Opération annulée.',
    'biometric-denied': 'Authentification biométrique refusée ou indisponible.',
    'no-session': 'Aucune session active. Reconnectez-vous.',
    'otp-not-sent': "Aucun code n'a été envoyé. Demandez-en un d'abord.",
    'password-required': 'Saisissez votre mot de passe pour confirmer.',
    'same-password': "Le nouveau mot de passe doit être différent de l'actuel.",
    'invalid-file': 'Fichier invalide ou trop volumineux (5 Mo max.).',
  };

  @override
  String toString() => 'AuthFailure($code): $message${cause == null ? '' : ' [cause: $cause]'}';
}
