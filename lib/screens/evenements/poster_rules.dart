import 'dart:typed_data';
import 'cloudinary_config.dart';

/// Type d'image reconnu par ses premiers octets (« nombre magique »).
enum PosterImageType { jpeg, png }

/// Règles PURES de l'affiche (testables sans téléphone ni réseau).
class PosterRules {
  PosterRules._();

  static const int maxInputBytes = 5 * 1024 * 1024; // 5 Mo avant compression
  static const int maxOutputBytes = 1024 * 1024; // 1 Mo après compression
  static const int maxLongSide = 1600; // px
  static const int maxUrlLength = 500;

  /// Type réel du fichier d'après ses premiers octets, pas d'après son nom.
  /// JPEG : FF D8 FF. PNG : 89 50 4E 47 0D 0A 1A 0A.
  static PosterImageType? detectType(Uint8List bytes) {
    if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return PosterImageType.jpeg;
    }
    const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    if (bytes.length >= 8) {
      var ok = true;
      for (var i = 0; i < 8; i++) {
        if (bytes[i] != png[i]) ok = false;
      }
      if (ok) return PosterImageType.png;
    }
    return null;
  }

  /// Contrôle avant compression : extension JPG/PNG ET contenu JPG/PNG,
  /// fichier non vide, 5 Mo maximum. Renvoie le message d'erreur ou null.
  static String? validate(String fileName, Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return 'Fichier vide ou illisible.';
    final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';
    if (!['jpg', 'jpeg', 'png'].contains(ext)) return 'Format non supporté : JPG ou PNG uniquement.';
    if (detectType(bytes) == null) {
      return "Ce fichier n'est pas une vraie image JPG ou PNG.";
    }
    if (bytes.length > maxInputBytes) return 'Image trop lourde (5 Mo maximum).';
    return null;
  }

  /// Largeur et hauteur lues dans l'en-tête (sans décoder l'image) :
  /// PNG (bloc IHDR) ou JPEG (segment SOF). null si illisible.
  static ({int width, int height})? dimensions(Uint8List b) {
    switch (detectType(b)) {
      case PosterImageType.png:
        if (b.length < 24) return null;
        int be32(int o) => (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
        return (width: be32(16), height: be32(20));
      case PosterImageType.jpeg:
        var i = 2;
        while (i + 9 < b.length) {
          if (b[i] != 0xFF) return null;
          final marker = b[i + 1];
          if (marker == 0xFF) {
            i++; // octets de remplissage
            continue;
          }
          final length = (b[i + 2] << 8) | b[i + 3];
          final isSof = marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8 && marker != 0xCC;
          if (isSof) {
            return (height: (b[i + 5] << 8) | b[i + 6], width: (b[i + 7] << 8) | b[i + 8]);
          }
          if (length < 2) return null;
          i += 2 + length;
        }
        return null;
      case null:
        return null;
    }
  }

  /// Petit côté visé pour que le GRAND côté fasse au plus [maxLong] px.
  /// Passé à la fois en minWidth et minHeight au compresseur, il donne la
  /// même échelle quelle que soit l'orientation de la photo.
  static int targetShortSide(int width, int height, {int maxLong = maxLongSide}) {
    final long = width > height ? width : height;
    final short = width > height ? height : width;
    if (long <= maxLong) return short; // déjà assez petite : pas de réduction
    return (short * maxLong / long).round().clamp(1, short);
  }

  /// URL d'affiche acceptée : https, notre cloud Cloudinary, 500 caractères
  /// au plus (mêmes contrôles que firestore.rules).
  static bool isAllowedPosterUrl(String? url) =>
      url != null && url.length <= maxUrlLength && url.startsWith(CloudinaryConfig.deliveryPrefix);

  /// « 312 Ko » ou « 1,2 Mo ».
  static String formatSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).ceil()} Ko';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} Mo';
  }
}
