import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'poster_rules.dart';

/// Compression de l'affiche avec flutter_image_compress (déjà dans le
/// projet, code natif : le travail se fait hors du fil de l'interface, qui
/// ne gèle pas).
///
/// - Grand côté ramené à 1600 px au plus, ré-encodage en JPEG.
/// - Qualité 85 puis baisse par paliers jusqu'à 55 tant que le résultat
///   dépasse 1 Mo ; si c'est encore trop gros, on réduit la taille de 20 %
///   et on recommence (quelques tours au maximum).
/// - VIE PRIVÉE : keepExif: false → les métadonnées EXIF (dont la position
///   GPS de la photo) sont supprimées par le ré-encodage. La rotation EXIF
///   est appliquée aux pixels avant (autoCorrectionAngle) pour que la photo
///   reste à l'endroit.
class PosterCompressor {
  PosterCompressor._();

  static const int _startQuality = 85;
  static const int _minQuality = 55;

  /// Renvoie le JPEG compressé, ou null si l'image n'a pas pu être lue.
  static Future<Uint8List?> compress(Uint8List input) async {
    final dims = PosterRules.dimensions(input);
    if (dims == null) return null;
    var target = PosterRules.targetShortSide(dims.width, dims.height);

    for (var round = 0; round < 4; round++) {
      for (var quality = _startQuality; quality >= _minQuality; quality -= 10) {
        final out = await FlutterImageCompress.compressWithList(
          input,
          minWidth: target,
          minHeight: target,
          quality: quality,
          format: CompressFormat.jpeg,
          keepExif: false,
          autoCorrectionAngle: true,
        );
        if (out.isEmpty) return null;
        if (out.length <= PosterRules.maxOutputBytes) return out;
      }
      target = (target * 0.8).round(); // encore trop lourde : plus petite
    }
    return null;
  }
}
