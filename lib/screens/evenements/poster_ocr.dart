import 'dart:io';

/// Une ligne de texte lue sur l'affiche.
///
/// [top] et [height] viennent du cadre de la ligne sur l'image (en pixels) :
/// la hauteur sert d'indice de taille de police (le titre est le plus grand).
/// [block] = numéro du paragraphe auquel la ligne appartient.
class PosterOcrLine {
  final String text;
  final double top;
  final double height;
  final int block;

  const PosterOcrLine(this.text, {required this.top, required this.height, this.block = 0});

  double get bottom => top + height;
  double get center => top + height / 2;

  @override
  String toString() => 'PosterOcrLine("$text", top: $top, height: $height, block: $block)';
}

/// Résultat de la lecture : les lignes dans l'ordre de lecture.
class PosterOcrResult {
  final List<PosterOcrLine> lines;
  const PosterOcrResult(this.lines);

  static const empty = PosterOcrResult([]);

  bool get isEmpty => lines.every((l) => l.text.trim().isEmpty);
}

/// Lecteur du texte d'une image d'affiche. L'implémentation réelle utilise la
/// reconnaissance de texte embarquée (aucun réseau) ; les tests utilisent un
/// faux lecteur qui renvoie des lignes fixées.
abstract class PosterTextReader {
  Future<PosterOcrResult> read(File image);
}

/// Pourquoi la lecture a échoué.
enum PosterReadFailure { timeout, unreadableImage, plugin }

class PosterReadException implements Exception {
  final PosterReadFailure kind;
  const PosterReadException(this.kind);

  /// Message à montrer à l'utilisateur.
  String get message => switch (kind) {
        PosterReadFailure.timeout => "La lecture de l'image a pris trop de temps. Réessayez avec une image plus petite.",
        PosterReadFailure.unreadableImage => "Cette image n'a pas pu être ouverte. Essayez-en une autre.",
        PosterReadFailure.plugin => "La lecture du texte n'est pas disponible sur cet appareil.",
      };

  @override
  String toString() => 'PosterReadException($kind)';
}
