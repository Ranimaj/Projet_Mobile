import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:campusconnect/screens/evenements/poster_ocr.dart';
import 'package:campusconnect/screens/evenements/poster_text_reader_mlkit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

TextLine _line(String text, double top, double height, {double left = 10}) => TextLine(
      text: text,
      elements: const [],
      boundingBox: Rect.fromLTWH(left, top, 200, height),
      recognizedLanguages: const [],
      cornerPoints: const <Point<int>>[],
      confidence: null,
      angle: null,
    );

TextBlock _block(List<TextLine> lines) {
  final top = lines.map((l) => l.boundingBox.top).reduce(min);
  final left = lines.map((l) => l.boundingBox.left).reduce(min);
  return TextBlock(
    text: lines.map((l) => l.text).join('\n'),
    lines: lines,
    boundingBox: Rect.fromLTWH(left, top, 200, 100),
    recognizedLanguages: const [],
    cornerPoints: const <Point<int>>[],
  );
}

/// Faux lecteur ML Kit : renvoie ce qu'on lui donne, compte les fermetures.
class _FakeRecognizer implements TextRecognizer {
  final Future<RecognizedText> Function() onProcess;
  int closed = 0;
  _FakeRecognizer(this.onProcess);

  @override
  TextRecognitionScript get script => TextRecognitionScript.latin;

  @override
  String get id => 'fake';

  @override
  Future<RecognizedText> processImage(InputImage inputImage) => onProcess();

  @override
  Future<void> close() async => closed++;
}

void main() {
  late Directory dir;
  late File image;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('poster_reader');
    image = File('${dir.path}/affiche.jpg')..writeAsBytesSync([0xFF, 0xD8, 0xFF, 0x00]);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  group('linesFrom', () {
    test('paragraphes de haut en bas, lignes dans l\'ordre, hauteur du cadre', () {
      final result = MlKitPosterTextReader.linesFrom(RecognizedText(text: '', blocks: [
        _block([_line('Lieu : Amphi B', 300, 26)]),
        _block([_line('TOURNOI', 100, 64), _line('DE FOOTBALL', 170, 64)]),
        _block([_line('   ', 400, 20)]),
      ]));
      expect(result.lines.map((l) => l.text), ['TOURNOI', 'DE FOOTBALL', 'Lieu : Amphi B']);
      expect(result.lines.first.height, 64);
      expect(result.lines.first.top, 100);
      expect(result.lines.map((l) => l.block), [0, 0, 1]);
    });

    test('même hauteur de paragraphe : de gauche à droite', () {
      final result = MlKitPosterTextReader.linesFrom(RecognizedText(text: '', blocks: [
        _block([_line('droite', 50, 20, left: 300)]),
        _block([_line('gauche', 50, 20, left: 10)]),
      ]));
      expect(result.lines.map((l) => l.text), ['gauche', 'droite']);
    });

    test('aucun texte : résultat vide', () {
      expect(MlKitPosterTextReader.linesFrom(RecognizedText(text: '', blocks: const [])).isEmpty, isTrue);
    });
  });

  group('read', () {
    test('succès : lignes renvoyées, lecteur fermé', () async {
      final fake = _FakeRecognizer(() async => RecognizedText(text: '', blocks: [
            _block([_line('Gratuit', 10, 20)])
          ]));
      final reader = MlKitPosterTextReader(createRecognizer: () => fake);
      final result = await reader.read(image);
      expect(result.lines.single.text, 'Gratuit');
      await pumpEventQueue();
      expect(fake.closed, 1);
    });

    test('fichier absent : image illisible', () async {
      final reader = MlKitPosterTextReader(createRecognizer: () => _FakeRecognizer(() => throw StateError('jamais')));
      await expectLater(
        reader.read(File('${dir.path}/absent.jpg')),
        throwsA(isA<PosterReadException>().having((e) => e.kind, 'kind', PosterReadFailure.unreadableImage)),
      );
    });

    test('trop long : délai dépassé, lecteur fermé quand le travail natif finit', () async {
      final pending = Completer<RecognizedText>();
      final fake = _FakeRecognizer(() => pending.future);
      final reader =
          MlKitPosterTextReader(timeout: const Duration(milliseconds: 20), createRecognizer: () => fake);
      await expectLater(
        reader.read(image),
        throwsA(isA<PosterReadException>().having((e) => e.kind, 'kind', PosterReadFailure.timeout)),
      );
      await pumpEventQueue();
      expect(fake.closed, 0, reason: 'pas de fermeture pendant le travail natif');
      pending.complete(RecognizedText(text: '', blocks: const []));
      await pumpEventQueue();
      expect(fake.closed, 1);
    });

    test('erreurs du plugin : image illisible ou lecture indisponible', () async {
      Future<PosterReadFailure> kindFor(Object error) async {
        final fake = _FakeRecognizer(() async => throw error);
        try {
          await MlKitPosterTextReader(createRecognizer: () => fake).read(image);
        } on PosterReadException catch (e) {
          await pumpEventQueue();
          expect(fake.closed, 1);
          return e.kind;
        }
        fail('aucune exception');
      }

      expect(await kindFor(PlatformException(code: 'TextRecognizerError', message: 'Unable to decode image')),
          PosterReadFailure.unreadableImage);
      expect(await kindFor(PlatformException(code: 'TextRecognizerError', message: 'internal error')),
          PosterReadFailure.plugin);
      expect(await kindFor(MissingPluginException()), PosterReadFailure.plugin);
    });

    test('lecteur impossible à créer : lecture indisponible', () async {
      final reader = MlKitPosterTextReader(createRecognizer: () => throw MissingPluginException());
      await expectLater(
        reader.read(image),
        throwsA(isA<PosterReadException>().having((e) => e.kind, 'kind', PosterReadFailure.plugin)),
      );
    });
  });

  test('messages en français pour chaque échec', () {
    for (final kind in PosterReadFailure.values) {
      expect(PosterReadException(kind).message, isNotEmpty);
    }
    expect(const PosterReadException(PosterReadFailure.timeout).message, contains('trop de temps'));
  });
}
