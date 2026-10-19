import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'cloudinary_config.dart';
import 'poster_rules.dart';

enum UploadError { noConnection, timeout, tooBig, rejected, invalidResponse }

/// Résultat d'un envoi : succès (URL https + identifiant) ou échec typé.
sealed class UploadResponse {
  const UploadResponse();
}

class UploadSuccess extends UploadResponse {
  final String url; // secure_url (https)
  final String publicId;
  const UploadSuccess(this.url, this.publicId);
}

class UploadFailure extends UploadResponse {
  final UploadError error;
  final String message; // en français, prêt à afficher
  const UploadFailure(this.error, this.message);
}

/// Envoi d'affiches vers Cloudinary avec un preset UNSIGNED (gratuit, sans
/// secret dans l'app). Même modèle que Osrm / Photon / OpenMeteo.
///
/// LIMITE (honnêtement) : un envoi unsigned ne permet NI de supprimer NI de
/// remplacer un fichier depuis l'app (il faut le secret d'API pour ça).
/// « Changer » ou « Retirer » l'affiche laisse donc l'ancienne image sur
/// Cloudinary (fichier orphelin). C'est acceptable à notre échelle (offre
/// gratuite : 25 crédits par mois). En production : une Cloud Function qui
/// garde le secret côté serveur et supprime l'ancienne image.
///
/// VIE PRIVÉE : l'image est publique pour qui connaît son URL (identifiant
/// aléatoire, impossible à deviner). Les métadonnées EXIF (position GPS…)
/// sont retirées avant l'envoi par la compression (voir PosterCompressor).
class CloudinaryService {
  static final CloudinaryService instance = CloudinaryService();

  final http.Client _client;
  final Duration timeout;

  CloudinaryService({http.Client? client, this.timeout = const Duration(seconds: 30)})
      : _client = client ?? http.Client();

  /// Envoie l'image JPEG [bytes]. Ne lève jamais d'exception.
  Future<UploadResponse> upload(Uint8List bytes) async {
    final request = http.MultipartRequest('POST', CloudinaryConfig.uploadUri)
      ..fields['upload_preset'] = CloudinaryConfig.uploadPreset
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: 'affiche.jpg'));

    final http.Response response;
    try {
      final streamed = await _client.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      return const UploadFailure(UploadError.timeout, "L'envoi de l'affiche a pris trop de temps.");
    } on SocketException {
      return const UploadFailure(UploadError.noConnection, "Pas de connexion : l'affiche n'a pas été envoyée.");
    } on http.ClientException {
      return const UploadFailure(UploadError.noConnection, "Pas de connexion : l'affiche n'a pas été envoyée.");
    }

    Map<String, dynamic>? body;
    try {
      final decoded = json.decode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) body = decoded;
    } on FormatException {
      body = null;
    }

    if (response.statusCode != 200) {
      // Cloudinary répond {"error": {"message": "..."}}.
      final serverMessage = (body?['error'] is Map ? body!['error']['message'] : null)?.toString() ?? '';
      if (response.statusCode == 413 || serverMessage.toLowerCase().contains('too large')) {
        return const UploadFailure(UploadError.tooBig, 'Affiche trop lourde pour le serveur.');
      }
      return UploadFailure(
        UploadError.rejected,
        serverMessage.isEmpty
            ? "Affiche refusée par le serveur (HTTP ${response.statusCode})."
            : 'Affiche refusée par le serveur : $serverMessage',
      );
    }

    final url = body?['secure_url']?.toString();
    final publicId = body?['public_id']?.toString();
    if (!PosterRules.isAllowedPosterUrl(url) || publicId == null || publicId.isEmpty) {
      return const UploadFailure(UploadError.invalidResponse, "Réponse du serveur d'images illisible.");
    }
    return UploadSuccess(url!, publicId);
  }
}
