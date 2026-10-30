import '../constants/app_constants.dart';

/// Calcule les topics Firebase Messaging utilisés pour cibler les annonces
/// par filière / année. UNE seule source de vérité : l'abonnement côté
/// appareil ET les topics écrits dans le document d'annonce (lus par la
/// Cloud Function) passent tous par cette classe.
class SegmentTopics {
  SegmentTopics._();

  /// Topic abonné par tous les utilisateurs connectés (annonces sans ciblage).
  static const String allCampus = 'all_campus';

  static const Map<String, String> _accents = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'î': 'i', 'ï': 'i', 'í': 'i',
    'ô': 'o', 'ö': 'o', 'ó': 'o',
    'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
    'ç': 'c', 'ñ': 'n', 'œ': 'oe', 'æ': 'ae',
  };

  /// "Génie Électrique" -> "genie-electrique" (caractères valides FCM).
  static String slug(String value) {
    final buf = StringBuffer();
    for (final ch in value.toLowerCase().split('')) {
      buf.write(_accents[ch] ?? ch);
    }
    return buf
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  /// Topic d'une filière. Une saisie libre du profil ("Génie Informatique")
  /// est rapprochée de la filière officielle correspondante ("Informatique").
  static String? majorTopic(String? major) {
    if (major == null || major.trim().isEmpty) return null;
    final s = slug(major);
    if (s.isEmpty) return null;
    for (final official in AppConstants.campusMajors) {
      final o = slug(official);
      if (s == o || s.contains(o)) return 'major_$o';
    }
    return 'major_$s';
  }

  /// Topic d'une année : le premier chiffre est utilisé
  /// ("3ème année", "3eme", "3A" -> "year_3").
  static String? yearTopic(String? year) {
    if (year == null || year.trim().isEmpty) return null;
    final digit = RegExp(r'\d').firstMatch(year)?.group(0);
    if (digit != null) return 'year_$digit';
    final s = slug(year);
    return s.isEmpty ? null : 'year_$s';
  }

  /// Topics auxquels un utilisateur doit être abonné.
  static Set<String> forUser(String? major, String? year) {
    return {
      allCampus,
      if (majorTopic(major) != null) majorTopic(major)!,
      if (yearTopic(year) != null) yearTopic(year)!,
    };
  }

  static List<String> majorTopics(Iterable<String> majors) =>
      majors.map(majorTopic).whereType<String>().toSet().toList();

  static List<String> yearTopics(Iterable<String> years) =>
      years.map(yearTopic).whereType<String>().toSet().toList();
}
