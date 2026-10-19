import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'place_rules.dart';

/// Une suggestion de lieu (affichée sous le champ « Lieu »).
class PlaceSuggestion {
  final String name; // ligne en gras
  final String label; // libellé complet, enregistré dans le champ
  final String secondary; // ligne grise : rue / quartier, ville, pays
  final double latitude;
  final double longitude;
  const PlaceSuggestion({
    required this.name,
    required this.label,
    required this.secondary,
    required this.latitude,
    required this.longitude,
  });
}

enum PhotonError { timeout, noConnection, httpError, invalidResponse }

/// Réponse : liste de suggestions (éventuellement vide) ou échec typé.
sealed class PhotonResponse {
  const PhotonResponse();
}

class PhotonSuccess extends PhotonResponse {
  final List<PlaceSuggestion> suggestions;
  const PhotonSuccess(this.suggestions);
}

class PhotonFailure extends PhotonResponse {
  final PhotonError error;
  final String message;
  const PhotonFailure(this.error, this.message);
}

/// Autocomplétion de lieux gratuite, sans clé, avec l'API Photon (Komoot,
/// données OpenStreetMap), conçue pour la recherche pendant la saisie (ce
/// que Nominatim interdit). Même modèle que OsrmService / OpenMeteoService.
///
/// - Résultats biaisés autour de Tunis (lat/lon), en français (lang=fr) ;
/// - on demande 10 résultats, on ne garde que la Tunisie (countrycode
///   « TN »), sans doublon, et on en affiche 5 au plus ;
/// - au plus 1 requête toutes les 500 ms : une instance PAR FORMULAIRE.
///
/// VIE PRIVÉE : seul le texte tapé dans « Lieu » est envoyé. La position de
/// l'utilisateur n'est JAMAIS envoyée (le point lat/lon est fixe : Tunis).
class PhotonService {
  static const String host = 'photon.komoot.io';
  static const String userAgent = 'CampusConnect/1.0 (com.esprit.campusconnect; projet etudiant ESPRIT)';
  static const double biasLat = 36.8065; // Tunis (point fixe, pas l'utilisateur)
  static const double biasLon = 10.1815;
  static const int maxSuggestions = 5; // affichées
  /// Demandées au serveur : plus que [maxSuggestions], car le filtre Tunisie
  /// et le retrait des doublons sont appliqués APRÈS la réponse.
  static const int requestLimit = 10;

  final http.Client _client;
  final Duration timeout;
  final Duration minInterval;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;

  PhotonService({
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
    this.minInterval = const Duration(milliseconds: 500),
    DateTime Function()? now,
    Future<void> Function(Duration)? sleep,
  })  : _client = client ?? http.Client(),
        _now = now ?? DateTime.now,
        _sleep = sleep ?? ((d) => Future<void>.delayed(d));

  DateTime? _lastRequestAt;
  Future<void> _gate = Future.value();

  /// Au plus une requête toutes les [minInterval] (500 ms).
  Future<void> _waitTurn() {
    _gate = _gate.then((_) async {
      final last = _lastRequestAt;
      if (last != null) {
        final wait = minInterval - _now().difference(last);
        if (wait > Duration.zero) await _sleep(wait);
      }
      _lastRequestAt = _now();
    });
    return _gate;
  }

  /// Suggestions pour [query]. Ne lève jamais d'exception.
  Future<PhotonResponse> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const PhotonSuccess([]);
    await _waitTurn();
    final uri = Uri.https(host, '/api/', {
      'q': q,
      'limit': '$requestLimit',
      'lang': 'fr',
      'lat': '$biasLat',
      'lon': '$biasLon',
    });

    final http.Response response;
    try {
      response = await _client.get(uri, headers: {'User-Agent': userAgent}).timeout(timeout);
    } on TimeoutException {
      return const PhotonFailure(PhotonError.timeout, 'Le service de lieux ne répond pas.');
    } on SocketException {
      return const PhotonFailure(PhotonError.noConnection, 'Pas de connexion au service de lieux.');
    } on http.ClientException {
      return const PhotonFailure(PhotonError.noConnection, 'Pas de connexion au service de lieux.');
    }
    if (response.statusCode != 200) {
      return PhotonFailure(PhotonError.httpError, 'Service de lieux indisponible (HTTP ${response.statusCode}).');
    }

    try {
      final decoded = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final features = decoded['features'] as List;
      final suggestions = <PlaceSuggestion>[];
      for (final f in features) {
        final feature = f as Map<String, dynamic>;
        final p = feature['properties'] as Map<String, dynamic>;
        if ((p['countrycode'] ?? '').toString().toUpperCase() != 'TN') continue; // Tunisie seulement
        final parts = PlaceRules.suggestionParts(
          name: p['name']?.toString(),
          street: p['street']?.toString(),
          district: p['district']?.toString(),
          city: p['city']?.toString(),
          country: p['country']?.toString(),
        );
        if (parts.isEmpty) continue;
        final label = parts.join(', ');
        if (suggestions.any((s) => s.label.toLowerCase() == label.toLowerCase())) continue; // doublon
        final coordinates = (feature['geometry'] as Map<String, dynamic>)['coordinates'] as List;
        suggestions.add(PlaceSuggestion(
          name: parts.first,
          label: label,
          secondary: parts.skip(1).join(', '),
          // GeoJSON : [longitude, latitude] → on remet dans l'ordre lat, lng.
          latitude: (coordinates[1] as num).toDouble(),
          longitude: (coordinates[0] as num).toDouble(),
        ));
        if (suggestions.length == maxSuggestions) break;
      }
      return PhotonSuccess(suggestions);
    } on FormatException {
      return const PhotonFailure(PhotonError.invalidResponse, 'Réponse du service de lieux illisible.');
    } on TypeError {
      return const PhotonFailure(PhotonError.invalidResponse, 'Réponse du service de lieux illisible.');
    }
  }
}
