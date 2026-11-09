import '../../models/annonce_model.dart';

/// Stockage des annonces utilisé par [AnnonceProvider].
///
/// Implémenté par [LocalAnnonceRepository] (base SQLite du téléphone) ; les
/// tests utilisent un dépôt en mémoire.
abstract class AnnonceStore {
  /// Toutes les annonces, épinglées d'abord puis les plus récentes.
  Future<List<AnnonceModel>> fetchAll();

  Future<AnnonceModel?> byId(String id);

  /// Enregistre une nouvelle annonce et renvoie son identifiant.
  Future<String> create(AnnonceModel item, {String? explicitId});

  /// Remplace l'annonce portant le même `id` que [item].
  Future<void> update(AnnonceModel item);

  Future<void> delete(String id);
}
