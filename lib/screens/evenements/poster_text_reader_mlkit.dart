import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'poster_ocr.dart';

/// Lecture du texte d'une affiche avec la reconnaissance de texte de ML Kit,
/// sur le téléphone : modèle « alphabet latin » embarqué dans l'application,
/// aucun envoi réseau.
///
/// Seul fichier du module qui dépend de ML Kit : le reste (règles, écran,
/// tests) ne connaît que [PosterTextReader].
class MlKitPosterTextReader implements PosterTextReader {
  /// Au-delà, on abandonne et on prévient l'utilisateur.
  final Duration timeout;

  final TextRecognizer Function() _createRecognizer;

  MlKitPosterTextReader({
    this.timeout = const Duration(seconds: 20),
    @visibleForTesting TextRecognizer Function()? createRecognizer,
  }) : _createRecognizer = createRecognizer ?? (() => TextRecognizer(script: TextRecognitionScript.latin));

  @override
  Future<PosterOcrResult> read(File image) async {
    if (!await image.exists()) throw const PosterReadException(PosterReadFailure.unreadableImage);

    final TextRecognizer recognizer;
    try {
      recognizer = _createRecognizer();
    } catch (e) {
      debugPrint('Lecture de texte indisponible : $e');
      throw const PosterReadException(PosterReadFailure.plugin);
    }

    final Future<RecognizedText> job;
    try {
      job = recognizer.processImage(InputImage.fromFilePath(image.path));
    } catch (e) {
      _closeLater(recognizer, null);
      throw _failureFor(e);
    }
    try {
      return linesFrom(await job.timeout(timeout));
    } on TimeoutException {
      throw const PosterReadException(PosterReadFailure.timeout);
    } catch (e) {
      throw _failureFor(e);
    } finally {
      // Toujours libérer le lecteur, mais seulement quand le travail natif est
      // terminé (il ne peut pas être annulé, même après le délai dépassé).
      _closeLater(recognizer, job);
    }
  }

  static void _closeLater(TextRecognizer recognizer, Future<RecognizedText>? job) {
    final done = job == null ? Future<void>.value() : job.then<void>((_) {}, onError: (Object _) {});
    unawaited(done.then((_) => recognizer.close()).then<void>((_) {}, onError: (Object e) {
      debugPrint('Fermeture du lecteur de texte : $e');
    }));
  }

  static PosterReadException _failureFor(Object e) {
    debugPrint('Lecture du texte de l\'affiche échouée : $e');
    if (e is PosterReadException) return e;
    if (e is MissingPluginException) return const PosterReadException(PosterReadFailure.plugin);
    final text = e is PlatformException ? '${e.code} ${e.message}'.toLowerCase() : e.toString().toLowerCase();
    const imageHints = ['image', 'decode', 'bitmap', 'file', 'ioexception', 'not found'];
    return PosterReadException(
        imageHints.any(text.contains) ? PosterReadFailure.unreadableImage : PosterReadFailure.plugin);
  }

  /// Résultat de ML Kit → lignes dans l'ordre de lecture : paragraphes triés
  /// de haut en bas (puis de gauche à droite), lignes dans l'ordre du
  /// paragraphe. Hauteur = hauteur du cadre de la ligne.
  @visibleForTesting
  static PosterOcrResult linesFrom(RecognizedText recognized) {
    final blocks = [...recognized.blocks]..sort((a, b) {
        final byTop = a.boundingBox.top.compareTo(b.boundingBox.top);
        return byTop != 0 ? byTop : a.boundingBox.left.compareTo(b.boundingBox.left);
      });
    return PosterOcrResult([
      for (var i = 0; i < blocks.length; i++)
        for (final line in blocks[i].lines)
          if (line.text.trim().isNotEmpty)
            PosterOcrLine(line.text, top: line.boundingBox.top, height: line.boundingBox.height, block: i),
    ]);
  }
}
