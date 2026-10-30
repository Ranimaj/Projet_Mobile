import 'package:cloud_firestore/cloud_firestore.dart';

/// Hive ne sait pas stocker les `Timestamp` Firestore (ni `DateTime` dans
/// une Map imbriquée de façon fiable). Ce codec convertit les valeurs avant
/// l'écriture locale (cache / file d'attente) et les restaure à la lecture,
/// de sorte que les modèles (`fromMap`) reçoivent toujours des `Timestamp`.
class FirestoreCodec {
  FirestoreCodec._();

  static const String _tsKey = '__ts';

  /// À appeler avant d'écrire dans Hive.
  static dynamic encode(dynamic value) {
    if (value is Timestamp) return {_tsKey: value.millisecondsSinceEpoch};
    if (value is DateTime) return {_tsKey: value.millisecondsSinceEpoch};
    if (value is Map) {
      return {for (final e in value.entries) e.key.toString(): encode(e.value)};
    }
    if (value is Iterable) return value.map(encode).toList();
    return value;
  }

  /// À appeler après lecture depuis Hive.
  static dynamic decode(dynamic value) {
    if (value is Map) {
      if (value.length == 1 && value[_tsKey] is int) {
        return Timestamp.fromMillisecondsSinceEpoch(value[_tsKey] as int);
      }
      return {for (final e in value.entries) e.key.toString(): decode(e.value)};
    }
    if (value is Iterable) return value.map(decode).toList();
    return value;
  }

  static Map<String, dynamic> encodeMap(Map<String, dynamic> map) =>
      Map<String, dynamic>.from(encode(map) as Map);

  static Map<String, dynamic> decodeMap(Map<dynamic, dynamic> map) =>
      Map<String, dynamic>.from(decode(map) as Map);
}
