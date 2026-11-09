import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Empreinte d'un mot de passe : PBKDF2-HMAC-SHA256 avec un sel aléatoire
/// propre à chaque compte. Le mot de passe lui-même n'est jamais stocké.
class PasswordHash {
  final String salt; // base64
  final String hash; // base64
  final int iterations;
  const PasswordHash({required this.salt, required this.hash, required this.iterations});

  Map<String, dynamic> toMap() => {'salt': salt, 'hash': hash, 'iterations': iterations};

  static PasswordHash? fromMap(Map<String, dynamic>? m) {
    if (m == null || m['salt'] is! String || m['hash'] is! String) return null;
    return PasswordHash(
      salt: m['salt'] as String,
      hash: m['hash'] as String,
      iterations: (m['iterations'] as num?)?.toInt() ?? PasswordHasher.defaultIterations,
    );
  }
}

class PasswordHasher {
  /// Assez lent pour freiner une attaque par dictionnaire sur une base
  /// copiée, assez rapide pour ne pas faire attendre à la connexion.
  static const int defaultIterations = 20000;
  static const int _saltBytes = 16;
  static const int _keyBytes = 32;

  final int iterations;
  final Random _random;

  PasswordHasher({this.iterations = defaultIterations, Random? random}) : _random = random ?? Random.secure();

  PasswordHash hash(String password) {
    final salt = Uint8List.fromList(List<int>.generate(_saltBytes, (_) => _random.nextInt(256)));
    return PasswordHash(
      salt: base64Encode(salt),
      hash: base64Encode(_pbkdf2(utf8.encode(password), salt, iterations)),
      iterations: iterations,
    );
  }

  /// Compare en temps constant. Une empreinte illisible ne correspond à rien.
  static bool verify(String password, PasswordHash stored) {
    final List<int> expected;
    final List<int> salt;
    try {
      expected = base64Decode(stored.hash);
      salt = base64Decode(stored.salt);
    } on FormatException {
      return false;
    }
    if (stored.iterations < 1) return false;
    final actual = _pbkdf2(utf8.encode(password), salt, stored.iterations);
    if (actual.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual[i] ^ expected[i];
    }
    return diff == 0;
  }

  static Uint8List _pbkdf2(List<int> password, List<int> salt, int iterations) {
    final hmac = Hmac(sha256, password);
    final out = Uint8List(_keyBytes);
    var offset = 0;
    for (var block = 1; offset < _keyBytes; block++) {
      final blockIndex = Uint8List(4)..buffer.asByteData().setUint32(0, block);
      var u = hmac.convert([...salt, ...blockIndex]).bytes;
      final t = Uint8List.fromList(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      final n = min(t.length, _keyBytes - offset);
      out.setRange(offset, offset + n, t);
      offset += n;
    }
    return out;
  }
}
