import '../../models/article_model.dart';

/// Stockage des articles de Vente & Don utilisé par [ArticleProvider].
///
/// Implémenté par [LocalArticleRepository] (base SQLite du téléphone) ; les
/// tests utilisent un dépôt en mémoire. [isOnline] est gardé pour la
/// compatibilité des appels : le stockage local l'ignore.
abstract class ArticleStore {
  Future<List<ArticleModel>> fetchAll({required bool isOnline});

  Future<String> create(ArticleModel item, {required bool isOnline, String? explicitId});

  Future<void> update(String id, Map<String, dynamic> patch, {required bool isOnline});

  Future<void> delete(String id, {required bool isOnline});
}
