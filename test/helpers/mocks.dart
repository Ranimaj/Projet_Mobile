import 'package:campusconnect/providers/connectivity_provider.dart';
import 'package:campusconnect/services/auth_service.dart';
import 'package:campusconnect/services/login_prefs.dart';
import 'package:campusconnect/services/storage_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthService extends Mock implements AuthService {}

class MockStorageService extends Mock implements StorageService {}

/// Préférences de connexion en mémoire (pas de Hive dans les tests).
class FakeLoginPrefs implements LoginPrefs {
  String? _email;
  final List<String?> writes = [];

  FakeLoginPrefs({String? remembered}) : _email = remembered;

  @override
  String? get rememberedEmail => _email;

  @override
  Future<void> remember(String? email) async {
    _email = email;
    writes.add(email);
  }
}

/// Le vrai ConnectivityProvider ouvre connectivity_plus et Hive dans son
/// constructeur ; on le remplace par un mock en ligne dans les tests d'écran.
class MockConnectivityProvider extends Mock implements ConnectivityProvider {}

/// `UserInfo` n'a que des constructeurs protégés : on ne simule que ce qui
/// est lu par l'app, le `providerId`.
class FakeUserInfo extends Fake implements UserInfo {
  final String _providerId;
  FakeUserInfo(this._providerId);

  @override
  String get providerId => _providerId;
}
