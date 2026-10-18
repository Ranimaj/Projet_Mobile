import 'package:hive/hive.dart';

import '../core/constants/app_constants.dart';

/// Préférences de l'écran de connexion : l'email mémorisé (« Se souvenir de
/// moi »). Jamais le mot de passe.
abstract class LoginPrefs {
  String? get rememberedEmail;

  /// Mémorise [email], ou oublie l'email mémorisé si `null`.
  Future<void> remember(String? email);
}

/// Implémentation Hive. Tolère une boîte non ouverte (tests, démarrage
/// partiel) : lecture `null`, écriture ignorée.
class HiveLoginPrefs implements LoginPrefs {
  static const _key = 'remembered_email';

  Box<dynamic>? get _box =>
      Hive.isBoxOpen(AppConstants.hivePrefsBox) ? Hive.box<dynamic>(AppConstants.hivePrefsBox) : null;

  @override
  String? get rememberedEmail {
    final value = _box?.get(_key);
    return value is String && value.isNotEmpty ? value : null;
  }

  @override
  Future<void> remember(String? email) async {
    final box = _box;
    if (box == null) return;
    if (email == null || email.isEmpty) {
      await box.delete(_key);
    } else {
      await box.put(_key, email);
    }
  }
}
