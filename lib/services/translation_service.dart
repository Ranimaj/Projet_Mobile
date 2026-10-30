import 'dart:convert';
import 'package:http/http.dart' as http;

/// Traduction via l'API gratuite MyMemory (aucune clé requise, ~5000
/// caractères/jour en anonyme, 500 octets max par requête -> découpage).
class TranslationService {
  static const Map<String, String> languages = {
    'en': 'English',
    'ar': 'العربية',
  };

  static const int _maxBytes = 450;
  static final Map<String, String> _cache = {};

  Future<String> translate(String text, {String from = 'fr', required String to}) async {
    final key = '$from|$to|${text.hashCode}';
    final hit = _cache[key];
    if (hit != null) return hit;

    final out = <String>[];
    for (final paragraph in text.split('\n')) {
      if (paragraph.trim().isEmpty) {
        out.add('');
        continue;
      }
      final translated = <String>[];
      for (final chunk in _chunks(paragraph.trim())) {
        translated.add(await _translateChunk(chunk, from, to));
      }
      out.add(translated.join(' '));
    }
    final result = out.join('\n');
    _cache[key] = result;
    return result;
  }

  Future<String> _translateChunk(String chunk, String from, String to) async {
    final uri = Uri.https('api.mymemory.translated.net', '/get', {
      'q': chunk,
      'langpair': '$from|$to',
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw Exception('Service de traduction indisponible (${res.statusCode})');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final status = int.tryParse('${json['responseStatus']}') ?? 0;
    if (status != 200) {
      throw Exception('${json['responseDetails'] ?? 'Quota de traduction atteint'}');
    }
    return _unescape('${(json['responseData'] as Map)['translatedText']}');
  }

  /// Découpe un paragraphe en morceaux de <= 450 octets (par phrases).
  List<String> _chunks(String paragraph) {
    if (utf8.encode(paragraph).length <= _maxBytes) return [paragraph];

    final sentences = paragraph.split(RegExp(r'(?<=[.!?؟])\s+'));
    final chunks = <String>[];
    var current = '';
    for (var s in sentences) {
      // Phrase trop longue : coupe brutalement par blocs de 150 caractères.
      while (utf8.encode(s).length > _maxBytes) {
        if (current.isNotEmpty) {
          chunks.add(current);
          current = '';
        }
        chunks.add(s.substring(0, 150));
        s = s.substring(150);
      }
      final candidate = current.isEmpty ? s : '$current $s';
      if (utf8.encode(candidate).length > _maxBytes) {
        chunks.add(current);
        current = s;
      } else {
        current = candidate;
      }
    }
    if (current.isNotEmpty) chunks.add(current);
    return chunks;
  }

  String _unescape(String s) => s
      .replaceAll('&#39;', "'")
      .replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}