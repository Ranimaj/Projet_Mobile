import 'dart:convert';
import 'package:http/http.dart' as http;

class PlaceResult {
  final String name;
  final double latitude;
  final double longitude;
  const PlaceResult({required this.name, required this.latitude, required this.longitude});
}

/// Recherche de lieux via l'API gratuite OpenStreetMap Nominatim (sans clé).
/// Règles d'usage : User-Agent identifiable, 1 requête/seconde max, pas
/// d'autocomplétion à chaque frappe -> la recherche se lance sur validation.
class PlaceSearchService {
  /// Pays de recherche (ISO 3166-1) : à adapter.
  static const String _countryCode = 'tn';

  Future<List<PlaceResult>> search(String query) async {
    final q = query.trim();
    if (q.length < 3) return [];

    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': q,
      'format': 'jsonv2',
      'limit': '5',
      'countrycodes': _countryCode,
      'accept-language': 'fr',
    });
    final res = await http.get(uri, headers: {
      'User-Agent': 'CampusConnect/1.0 (projet etudiant)',
    }).timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw Exception('Recherche de lieu indisponible (${res.statusCode})');
    }

    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    return list.map((e) {
      final m = e as Map<String, dynamic>;
      return PlaceResult(
        name: _short(m['display_name'] as String),
        latitude: double.parse(m['lat'] as String),
        longitude: double.parse(m['lon'] as String),
      );
    }).toList();
  }

  /// "Bibliothèque, Rue X, Tunis, 1002, Tunisie" -> "Bibliothèque, Rue X, Tunis"
  String _short(String displayName) => displayName.split(', ').take(3).join(', ');
}