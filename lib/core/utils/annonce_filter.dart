import '../../models/annonce_model.dart';
import '../../models/user_model.dart';

/// Recherche et filtres d'affichage du fil d'annonces (urgentes, « pour moi »,
/// « mes annonces »). Fonction pure : l'écran garde l'état, le provider reste
/// limité aux données et au filtre par catégorie.
class AnnonceFilter {
  final String query;
  final bool onlyUrgent;
  final bool onlyMine;
  final bool onlyForMe;

  const AnnonceFilter({
    this.query = '',
    this.onlyUrgent = false,
    this.onlyMine = false,
    this.onlyForMe = false,
  });

  /// Nombre de critères actifs (hors catégorie, gérée par le provider).
  int get activeCount =>
      (query.trim().isNotEmpty ? 1 : 0) +
      (onlyUrgent ? 1 : 0) +
      (onlyMine ? 1 : 0) +
      (onlyForMe ? 1 : 0);

  AnnonceFilter copyWith({
    String? query,
    bool? onlyUrgent,
    bool? onlyMine,
    bool? onlyForMe,
  }) {
    return AnnonceFilter(
      query: query ?? this.query,
      onlyUrgent: onlyUrgent ?? this.onlyUrgent,
      onlyMine: onlyMine ?? this.onlyMine,
      onlyForMe: onlyForMe ?? this.onlyForMe,
    );
  }

  /// Applique les critères en conservant l'ordre de [source] (déjà trié par
  /// le provider : épinglées d'abord, puis date décroissante).
  List<AnnonceModel> apply(List<AnnonceModel> source, {AppUser? user}) {
    return source.where((a) {
      if (!a.matchesQuery(query)) return false;
      if (onlyUrgent && !a.isUrgent) return false;
      if (onlyMine && (user == null || a.authorId != user.id)) return false;
      if (onlyForMe &&
          (user == null || !a.matchesUser(major: user.major, year: user.year))) {
        return false;
      }
      return true;
    }).toList();
  }
}
