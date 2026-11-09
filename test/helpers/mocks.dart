import 'package:campusconnect/providers/connectivity_provider.dart';
import 'package:campusconnect/services/auth_service.dart';
import 'package:campusconnect/services/login_prefs.dart';
import 'package:campusconnect/services/storage_service.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthService extends Mock implements AuthService {}

class MockStorageService extends Mock implements StorageService {}

/// Préférences de connexion en mémoire (pas de stockage SQLite dans les tests).
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

/// Le vrai ConnectivityProvider ouvre connectivity_plus dans son constructeur ;
/// on le remplace par un mock en ligne dans les tests d'écran.
class MockConnectivityProvider extends Mock implements ConnectivityProvider {}
