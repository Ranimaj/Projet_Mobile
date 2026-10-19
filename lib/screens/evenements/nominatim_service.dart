import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Position trouvée pour un lieu.
class GeocodeResult {
  final double lat;
  final double lng;
  final String displayName;
  const GeocodeResult({required this.lat, required this.lng, required this.displayName});
}

/// Types d'échec possibles (pour tester et choisir le message).
enum GeocodeError { emptyQuery, notFound, timeout, noConnection, httpError, invalidResponse }

/// Réponse du géocodage : soit un succès, soit un échec typé. « sealed » :
/// le compilateur vérifie qu'on traite les deux cas (switch exhaustif).
sealed class GeocodeResponse {
  const GeocodeResponse();
}

class GeocodeSuccess extends GeocodeResponse {
  final GeocodeResult result;
  const GeocodeSuccess(this.result);
}

class GeocodeFailure extends GeocodeResponse {
  final GeocodeError error;
  final String message; // en français, prêt à afficher
  const GeocodeFailure(this.error, this.message);
}

/// Géocodage gratuit avec l'API REST Nominatim (OpenStreetMap), sans clé.
///
/// Politique d'usage de Nominatim respectée :
/// - User-Agent descriptif (nom de l'app + identifiant du paquet) ;
/// - au plus 1 requête par seconde (petit « throttle ») ;
/// - pas d'autocomplétion : on géocode une seule fois, à l'enregistrement ;
/// - résultats mis en cache en mémoire par requête.
///
/// VIE PRIVÉE : le nom du lieu saisi par l'organisateur est envoyé aux
/// serveurs de Nominatim (OpenStreetMap Foundation) pour être converti en
/// coordonnées. Aucune autre donnée (utilisateur, événement) n'est envoyée.
class NominatimService {
  /// Instance partagée par toute l'app : le throttle et le cache doivent
  /// être communs à tous les écrans.
  static final NominatimService instance = NominatimService();

  static const String host = 'nominatim.openstreetmap.org';
  static const String userAgent = 'CampusConnect/1.0 (com.esprit.campusconnect; projet etudiant ESPRIT)';

  final http.Client _client;
  final Duration timeout;
  final Duration minInterval;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;

  /// [client], [now] et [sleep] sont remplaçables pour les tests.
  NominatimService({
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
    this.minInterval = const Duration(seconds: 1),
    DateTime Function()? now,
    Future<void> Function(Duration)? sleep,
  })  : _client = client ?? http.Client(),
        _now = now ?? DateTime.now,
        _sleep = sleep ?? ((d) => Future<void>.delayed(d));

  final Map<String, GeocodeResponse> _cache = {};
  DateTime? _lastRequestAt;
  Future<void> _gate = Future.value();

  /// Attend son tour : au moins [minInterval] entre deux requêtes, même si
  /// plusieurs appels arrivent en même temps (ils passent l'un après l'autre).
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

  /// Convertit [place] en coordonnées. [countryCodes] limite la recherche
  /// (par défaut la Tunisie, « tn » ; null = monde entier). Ne lève jamais
  /// d'exception : renvoie un [GeocodeFailure] avec un message en français.
  Future<GeocodeResponse> geocode(String place, {String? countryCodes = 'tn'}) async {
    final query = place.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (query.isEmpty) return const GeocodeFailure(GeocodeError.emptyQuery, 'Lieu vide.');

    final key = '${countryCodes ?? '*'}|${query.toLowerCase()}';
    final cached = _cache[key];
    if (cached != null) return cached;

    await _waitTurn();
    final uri = Uri.https(host, '/search', {
      'q': query,
      'format': 'jsonv2',
      'limit': '1',
      if (countryCodes != null) 'countrycodes': countryCodes,
    });

    final http.Response response;
    try {
      response = await _client.get(uri, headers: {
        'User-Agent': userAgent,
        'Accept-Language': 'fr',
      }).timeout(timeout);
    } on TimeoutException {
      return const GeocodeFailure(GeocodeError.timeout, 'Le service de carte ne répond pas.');
    } on SocketException {
      return const GeocodeFailure(GeocodeError.noConnection, 'Pas de connexion au service de carte.');
    } on http.ClientException {
      return const GeocodeFailure(GeocodeError.noConnection, 'Pas de connexion au service de carte.');
    }

    if (response.statusCode != 200) {
      return GeocodeFailure(GeocodeError.httpError, 'Service de carte indisponible (HTTP ${response.statusCode}).');
    }

    final GeocodeResponse result;
    try {
      final decoded = json.decode(utf8.decode(response.bodyBytes));
      if (decoded is! List) throw const FormatException('liste attendue');
      if (decoded.isEmpty) {
        result = const GeocodeFailure(GeocodeError.notFound, 'Lieu introuvable sur la carte');
      } else {
        final first = decoded.first as Map<String, dynamic>;
        result = GeocodeSuccess(GeocodeResult(
          // Nominatim renvoie lat/lon sous forme de texte : "36.8987".
          lat: double.parse(first['lat'].toString()),
          lng: double.parse(first['lon'].toString()),
          displayName: (first['display_name'] ?? query).toString(),
        ));
      }
    } on FormatException {
      return const GeocodeFailure(GeocodeError.invalidResponse, 'Réponse du service de carte illisible.');
    } on TypeError {
      return const GeocodeFailure(GeocodeError.invalidResponse, 'Réponse du service de carte illisible.');
    }

    // On garde en cache les succès et les « introuvable », pas les pannes
    // réseau (elles peuvent disparaître au prochain essai).
    _cache[key] = result;
    return result;
  }
}
