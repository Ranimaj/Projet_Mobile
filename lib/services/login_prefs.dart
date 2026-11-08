import '../core/utils/local_database.dart';

/// Préférences de l'écran de connexion : l'email mémorisé (« Se souvenir de
/// moi »). Jamais le mot de passe.
abstract class LoginPrefs {
  String? get rememberedEmail;

  /// Mémorise [email], ou oublie l'email mémorisé si `null`.
  Future<void> remember(String? email);
}

/// Implémentation SQLite (table `kv` du stockage partagé [LocalDatabase]).
/// Tolère un stockage non ouvert (tests, démarrage partiel) : lecture
/// `null`, écriture ignorée.
class SqliteLoginPrefs implements LoginPrefs {
  static const key = 'remembered_email';

  LocalDatabase? get _store => LocalDatabase.isOpen ? LocalDatabase.instance : null;

  @override
  String? get rememberedEmail {
    final value = _store?.getValue(key);
    return value != null && value.isNotEmpty ? value : null;
  }

  @override
  Future<void> remember(String? email) async {
    final store = _store;
    if (store == null) return;
    await store.setValue(key, email == null || email.isEmpty ? null : email);
  }
}
