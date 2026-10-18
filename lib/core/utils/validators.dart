/// Validation et normalisation des saisies du module Gestion des Utilisateurs.
///
/// Les validateurs renvoient `null` si la valeur est valide, sinon le message
/// à afficher — signature compatible avec `TextFormField.validator`.
class Validators {
  Validators._();

  static final RegExp _emailRegex =
      RegExp(r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}$');

  /// Numéro au format international E.164 (ex. +21612345678).
  static final RegExp _e164Regex = RegExp(r'^\+[1-9]\d{7,14}$');

  static const int minPasswordLength = 8;
  static const int otpLength = 6;

  // --- Normalisation -------------------------------------------------------

  static String normalizeEmail(String raw) => raw.trim().toLowerCase();

  /// Supprime les espaces multiples et met une majuscule à chaque mot.
  static String normalizeFullName(String raw) {
    return raw
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  /// Convertit une saisie libre en E.164. Un numéro tunisien à 8 chiffres est
  /// préfixé par +216 ; `00` est remplacé par `+`. Renvoie `null` si invalide.
  static String? normalizePhone(String raw, {String defaultCountryCode = '+216'}) {
    var digits = raw.replaceAll(RegExp(r'[\s().\-]'), '');
    if (digits.startsWith('00')) digits = '+${digits.substring(2)}';
    if (!digits.startsWith('+')) {
      if (RegExp(r'^\d{8}$').hasMatch(digits)) {
        digits = '$defaultCountryCode$digits';
      } else {
        return null;
      }
    }
    return _e164Regex.hasMatch(digits) ? digits : null;
  }

  // --- Validateurs de formulaire ------------------------------------------

  static String? email(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Email requis';
    if (!_emailRegex.hasMatch(v)) return 'Email invalide';
    return null;
  }

  /// Pour la connexion on ne durcit pas : un ancien compte peut avoir un mot
  /// de passe plus court que la règle d'inscription actuelle.
  static String? loginPassword(String? value) {
    if (value == null || value.isEmpty) return 'Mot de passe requis';
    return null;
  }

  static String? newPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Mot de passe requis';
    if (v.length < minPasswordLength) return '$minPasswordLength caractères minimum';
    if (!RegExp(r'[A-Za-z]').hasMatch(v)) return 'Ajoutez au moins une lettre';
    if (!RegExp(r'\d').hasMatch(v)) return 'Ajoutez au moins un chiffre';
    return null;
  }

  static String? Function(String?) confirmPassword(String Function() original) {
    return (value) {
      if (value == null || value.isEmpty) return 'Confirmation requise';
      return value == original() ? null : 'Les mots de passe ne correspondent pas';
    };
  }

  static String? fullName(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Nom requis';
    if (v.length < 3) return 'Nom trop court';
    if (v.length > 60) return 'Nom trop long';
    if (RegExp(r'[0-9@#$%^&*()_+=<>{}\[\]|\\/]').hasMatch(v)) return 'Caractères non autorisés';
    return null;
  }

  static String? phone(String? value) {
    if ((value ?? '').trim().isEmpty) return 'Numéro requis';
    return normalizePhone(value!) == null ? 'Numéro invalide (ex. 20 123 456)' : null;
  }

  /// Filière : facultative, mais si renseignée elle doit être lisible.
  static String? major(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return null;
    if (v.length < 2) return 'Filière trop courte';
    if (v.length > 40) return 'Filière trop longue';
    return null;
  }

  /// Compétence ajoutée au profil (ex. "Flutter", "Gestion de projet").
  static String? skill(String? value, {List<String> existing = const []}) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Compétence vide';
    if (v.length < 2) return 'Compétence trop courte';
    if (v.length > 30) return '30 caractères maximum';
    if (existing.any((e) => e.toLowerCase() == v.toLowerCase())) return 'Déjà ajoutée';
    return null;
  }

  static String? otp(String? value) {
    final v = (value ?? '').trim();
    if (v.length != otpLength || !RegExp(r'^\d+$').hasMatch(v)) {
      return 'Code à $otpLength chiffres';
    }
    return null;
  }

  /// Force du mot de passe de 0 (vide) à 4 — pour l'indicateur visuel.
  static int passwordStrength(String value) {
    if (value.isEmpty) return 0;
    var score = 0;
    if (value.length >= minPasswordLength) score++;
    if (RegExp(r'[a-z]').hasMatch(value) && RegExp(r'[A-Z]').hasMatch(value)) score++;
    if (RegExp(r'\d').hasMatch(value)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(value)) score++;
    return score.clamp(1, 4);
  }
}
