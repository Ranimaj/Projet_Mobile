import 'dart:convert';
import 'dart:typed_data';
import 'package:campusconnect/models/event_model.dart';
import 'package:campusconnect/screens/evenements/cloudinary_service.dart';
import 'package:campusconnect/screens/evenements/poster_rules.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Étape 10 : affiches (contrôles, dimensions, URL, envoi Cloudinary).
void main() {
  // En-têtes minimaux, fabriqués à la main (pas de vraie image nécessaire).
  Uint8List png({int width = 4000, int height = 3000}) => Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature PNG
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // bloc IHDR
        (width >> 24) & 0xFF, (width >> 16) & 0xFF, (width >> 8) & 0xFF, width & 0xFF,
        (height >> 24) & 0xFF, (height >> 16) & 0xFF, (height >> 8) & 0xFF, height & 0xFF,
        0x08, 0x02, 0x00, 0x00, 0x00,
      ]);

  Uint8List jpeg({int width = 3000, int height = 4000}) => Uint8List.fromList([
        0xFF, 0xD8, // début d'image
        0xFF, 0xE0, 0x00, 0x10, ...List.filled(14, 0x00), // segment APP0 (ignoré)
        0xFF, 0xC0, 0x00, 0x11, 0x08, // SOF0
        (height >> 8) & 0xFF, height & 0xFF, (width >> 8) & 0xFF, width & 0xFF,
        0x03, ...List.filled(9, 0x00),
      ]);

  group('type réel (nombre magique)', () {
    test('JPEG et PNG reconnus', () {
      expect(PosterRules.detectType(jpeg()), PosterImageType.jpeg);
      expect(PosterRules.detectType(png()), PosterImageType.png);
    });
    test('GIF, texte, vide : non reconnus', () {
      expect(PosterRules.detectType(Uint8List.fromList(ascii.encode('GIF89a......'))), isNull);
      expect(PosterRules.detectType(Uint8List.fromList(utf8.encode('bonjour'))), isNull);
      expect(PosterRules.detectType(Uint8List(0)), isNull);
    });
  });

  group('validate (avant compression)', () {
    test('photo.jpg / affiche.PNG valides', () {
      expect(PosterRules.validate('photo.jpg', jpeg()), isNull);
      expect(PosterRules.validate('affiche.PNG', png()), isNull);
      expect(PosterRules.validate('photo.jpeg', jpeg()), isNull);
    });
    test('.gif refusé', () {
      expect(PosterRules.validate('anim.gif', Uint8List.fromList(ascii.encode('GIF89a......'))),
          'Format non supporté : JPG ou PNG uniquement.');
    });
    test('texte renommé en .jpg : refusé (le contenu est vérifié, pas seulement le nom)', () {
      expect(PosterRules.validate('faux.jpg', Uint8List.fromList(utf8.encode('ceci est un texte'))),
          "Ce fichier n'est pas une vraie image JPG ou PNG.");
    });
    test('.txt refusé', () => expect(PosterRules.validate('notes.txt', jpeg()), isNotNull));
    test('sans extension refusé', () => expect(PosterRules.validate('image', jpeg()), isNotNull));
    test('vide ou illisible refusé', () {
      expect(PosterRules.validate('photo.jpg', Uint8List(0)), 'Fichier vide ou illisible.');
      expect(PosterRules.validate('photo.jpg', null), 'Fichier vide ou illisible.');
    });
    test('5 Mo accepté ; 6 Mo refusé', () {
      Uint8List sized(int n) => Uint8List(n)..setAll(0, jpeg());
      expect(PosterRules.validate('photo.jpg', sized(5 * 1024 * 1024)), isNull);
      expect(PosterRules.validate('photo.jpg', sized(6 * 1024 * 1024)), 'Image trop lourde (5 Mo maximum).');
    });
  });

  group('dimensions lues dans l’en-tête', () {
    test('PNG 4000 × 3000', () {
      final d = PosterRules.dimensions(png());
      expect((d!.width, d.height), (4000, 3000));
    });
    test('JPEG 3000 × 4000 (après un segment APP0)', () {
      final d = PosterRules.dimensions(jpeg());
      expect((d!.width, d.height), (3000, 4000));
    });
    test('fichier tronqué : null', () {
      expect(PosterRules.dimensions(Uint8List.fromList([0xFF, 0xD8, 0xFF])), isNull);
    });
  });

  group('taille visée (grand côté ≤ 1600 px)', () {
    test('4000 × 3000 → petit côté 1200 (grand côté 1600)', () {
      expect(PosterRules.targetShortSide(4000, 3000), 1200);
    });
    test('portrait 3000 × 4000 → même résultat', () {
      expect(PosterRules.targetShortSide(3000, 4000), 1200);
    });
    test('déjà petite (1200 × 800) : pas de réduction', () {
      expect(PosterRules.targetShortSide(1200, 800), 800);
    });
  });

  group('URL d’affiche autorisée (comme firestore.rules)', () {
    test('notre cloud : oui', () {
      expect(PosterRules.isAllowedPosterUrl('https://res.cloudinary.com/jmwc9h1o/image/upload/v1/campusconnect/events/a.jpg'),
          isTrue);
    });
    test('autre hôte, autre cloud, http : non', () {
      expect(PosterRules.isAllowedPosterUrl('https://exemple.com/a.jpg'), isFalse);
      expect(PosterRules.isAllowedPosterUrl('https://res.cloudinary.com/autrecloud/a.jpg'), isFalse);
      expect(PosterRules.isAllowedPosterUrl('http://res.cloudinary.com/jmwc9h1o/a.jpg'), isFalse);
      expect(PosterRules.isAllowedPosterUrl(null), isFalse);
    });
    test('plus de 500 caractères : non', () {
      expect(PosterRules.isAllowedPosterUrl('https://res.cloudinary.com/jmwc9h1o/${'a' * 500}'), isFalse);
    });
  });

  test('taille affichée : Ko / Mo', () {
    expect(PosterRules.formatSize(312 * 1024), '312 Ko');
    expect(PosterRules.formatSize((1.2 * 1024 * 1024).round()), '1,2 Mo');
  });

  group('modèle : posterUrl', () {
    final e = EventModel(
      id: 'e',
      organizerId: 'org',
      organizerName: 'Club',
      title: 'Titre',
      description: 'Description',
      category: 'Culture',
      startDate: DateTime(2026, 11, 10, 18, 0),
      location: 'Hall',
      posterUrl: 'https://res.cloudinary.com/jmwc9h1o/a.jpg',
    );
    test('clearPoster retire l’affiche', () => expect(e.copyWith(clearPoster: true).posterUrl, isNull));
    test('modification : seul posterUrl est envoyé', () {
      expect(e.copyWith(posterUrl: 'https://res.cloudinary.com/jmwc9h1o/b.jpg').changedFieldsSince(e),
          {'posterUrl': 'https://res.cloudinary.com/jmwc9h1o/b.jpg'});
      expect(e.copyWith(clearPoster: true).changedFieldsSince(e), {'posterUrl': null});
    });
    test('ancien document sans affiche : null', () {
      expect(EventModel.fromMap('x', {...e.toMap(), 'posterUrl': null}).posterUrl, isNull);
    });
  });

  group('CloudinaryService', () {
    http.Response jsonResponse(Object body, [int status = 200]) => http.Response.bytes(
          utf8.encode(json.encode(body)),
          status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
    final image = Uint8List.fromList(jpeg());

    test('succès : secure_url et public_id', () async {
      final s = CloudinaryService(
        client: MockClient((_) async => jsonResponse({
              'secure_url': 'https://res.cloudinary.com/jmwc9h1o/image/upload/v1/campusconnect/events/x.jpg',
              'url': 'http://res.cloudinary.com/jmwc9h1o/image/upload/v1/campusconnect/events/x.jpg',
              'public_id': 'campusconnect/events/x',
            })),
      );
      final r = await s.upload(image);
      expect((r as UploadSuccess).url, startsWith('https://res.cloudinary.com/jmwc9h1o/'));
      expect(r.publicId, 'campusconnect/events/x');
    });

    test('requête : POST multipart avec upload_preset et file, sans secret', () async {
      late http.Request sent;
      await CloudinaryService(
        client: MockClient((req) async {
          sent = req;
          return jsonResponse({'secure_url': 'https://res.cloudinary.com/jmwc9h1o/a.jpg', 'public_id': 'a'});
        }),
      ).upload(image);
      expect(sent.method, 'POST');
      expect(sent.url.toString(), 'https://api.cloudinary.com/v1_1/jmwc9h1o/image/upload');
      expect(sent.headers['content-type'], startsWith('multipart/form-data'));
      final body = latin1.decode(sent.bodyBytes);
      expect(body, contains('name="upload_preset"'));
      expect(body, contains('campusconnect_events'));
      expect(body, contains('name="file"'));
      expect(body.toLowerCase(), isNot(contains('api_secret')));
      expect(body.toLowerCase(), isNot(contains('signature')));
    });

    test('refus Cloudinary : message du serveur lu dans error.message', () async {
      final r = await CloudinaryService(
        client: MockClient((_) async => jsonResponse({
              'error': {'message': 'Upload preset not found'}
            }, 400)),
      ).upload(image);
      expect((r as UploadFailure).error, UploadError.rejected);
      expect(r.message, contains('Upload preset not found'));
    });

    test('fichier trop gros (413 ou « too large »)', () async {
      final r413 = await CloudinaryService(client: MockClient((_) async => http.Response('', 413))).upload(image);
      expect((r413 as UploadFailure).error, UploadError.tooBig);
      final rMsg = await CloudinaryService(
        client: MockClient((_) async => jsonResponse({
              'error': {'message': 'File size too large. Got 12000000. Maximum is 10485760.'}
            }, 400)),
      ).upload(image);
      expect((rMsg as UploadFailure).error, UploadError.tooBig);
    });

    test('pas de connexion', () async {
      final r = await CloudinaryService(client: MockClient((_) async => throw http.ClientException('coupé')))
          .upload(image);
      expect((r as UploadFailure).error, UploadError.noConnection);
    });

    test('délai dépassé', () async {
      final r = await CloudinaryService(
        timeout: const Duration(milliseconds: 50),
        client: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return jsonResponse({'secure_url': 'https://res.cloudinary.com/jmwc9h1o/a.jpg', 'public_id': 'a'});
        }),
      ).upload(image);
      expect((r as UploadFailure).error, UploadError.timeout);
    });

    test('réponse illisible ou URL d’un autre cloud : « invalidResponse »', () async {
      final r1 = await CloudinaryService(client: MockClient((_) async => http.Response('{pas du json', 200)))
          .upload(image);
      expect((r1 as UploadFailure).error, UploadError.invalidResponse);
      final r2 = await CloudinaryService(
        client: MockClient((_) async => jsonResponse({'secure_url': 'https://exemple.com/a.jpg', 'public_id': 'a'})),
      ).upload(image);
      expect((r2 as UploadFailure).error, UploadError.invalidResponse);
    });
  });
}
