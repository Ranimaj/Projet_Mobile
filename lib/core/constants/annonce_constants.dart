import 'app_constants.dart';

/// Listes de ciblage du module Annonces (notifications par filière / année).
///
/// Réutilise les listes du profil pour que le ciblage corresponde exactement
/// à ce que l'étudiant a choisi.
class AnnonceConstants {
  AnnonceConstants._();

  static List<String> get majors => AppConstants.departments.where((d) => d != 'Autre').toList();

  static List<String> get years => AppConstants.studyYears.where((y) => y != 'Alumni').toList();
}
