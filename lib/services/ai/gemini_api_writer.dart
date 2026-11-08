import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import 'article_ai.dart';
import 'gemini_key.dart';

/// Clé de l'API Gemini (Google AI Studio), donnée au lancement :
/// `flutter run --dart-define=GEMINI_API_KEY=ta_cle`. Jamais écrite dans le
/// code ni dans Git.
/// Sinon, c'est la clé enregistrée dans `gemini_key.dart` qui est utilisée.
const String kGeminiApiKey = String.fromEnvironment('GEMINI_API_KEY', defaultValue: kGeminiApiKeyLocal);

/// Modèle Gemini utilisé (modifiable avec `--dart-define=GEMINI_MODEL=...`).
/// `gemini-3.5-flash` répond en quelques secondes (testé le 08/11/2026 ;
/// `gemini-3.8-flash` ne répondait pas, serveurs saturés).
const String kGeminiModel = String.fromEnvironment('GEMINI_MODEL', defaultValue: 'gemini-3.5-flash');

/// Modèles de secours essayés si le premier ne répond pas.
const List<String> kGeminiBackupModels = ['gemini-3.5-flash-lite'];

/// Rédaction de la description **par internet** avec l'API Gemini de Google
/// (sans Firebase). Si la clé manque, s'il n'y a pas de réseau ou si Gemini
/// répond une erreur, la rédaction locale ([fallback]) prend le relais : le
/// bouton marche donc toujours.
class GeminiApiDescriptionWriter implements DescriptionWriter {
  GeminiApiDescriptionWriter({
    required this.apiKey,
    this.model = kGeminiModel,
    this.backupModels = kGeminiBackupModels,
    http.Client? client,
    this.fallback = const LocalDescriptionWriter(),
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  final String apiKey;
  final String model;
  final List<String> backupModels;
  final DescriptionWriter fallback;
  final Duration timeout;
  final http.Client _client;

  /// Photo envoyée seulement si elle fait moins de 3 Mo (envoi rapide).
  static const int maxPhotoBytes = 3 * 1024 * 1024;

  Uri _endpoint(String m) =>
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$m:generateContent');

  @override
  Future<String> write(DescriptionRequest request) async {
    if (apiKey.isEmpty) {
      debugPrint('[IA] Pas de clé GEMINI_API_KEY : rédaction locale.');
      return fallback.write(request);
    }
    for (final m in [model, ...backupModels]) {
      try {
        final text = await _ask(request, m);
        if (text.isEmpty) continue;
        return text.length > 1000 ? text.substring(0, 1000) : text;
      } catch (e) {
        debugPrint('[IA] Gemini $m indisponible ($e).');
      }
    }
    debugPrint('[IA] Gemini n\'a pas répondu : rédaction locale.');
    return fallback.write(request);
  }

  Future<String> _ask(DescriptionRequest request, String m) async {
    final parts = <Map<String, Object>>[
      {'text': request.prompt},
    ];
    final photo = request.photo;
    if (photo != null && await photo.exists() && await photo.length() <= maxPhotoBytes) {
      parts.add({
        'inline_data': {'mime_type': 'image/jpeg', 'data': base64Encode(await photo.readAsBytes())},
      });
    }
    final response = await _client
        .post(
          _endpoint(m),
          headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
          body: jsonEncode({
            'contents': [
              {'parts': parts},
            ],
            'generationConfig': {'temperature': 0.7, 'maxOutputTokens': 1024},
          }),
        )
        .timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Gemini ${response.statusCode} ${utf8.decode(response.bodyBytes)}');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final candidates = json['candidates'] as List? ?? const [];
    if (candidates.isEmpty) return '';
    final content = (candidates.first as Map<String, dynamic>)['content'] as Map<String, dynamic>?;
    final textParts = content?['parts'] as List? ?? const [];
    return [
      for (final p in textParts)
        if (p is Map && p['text'] is String) p['text'] as String,
    ].join().trim();
  }
}
