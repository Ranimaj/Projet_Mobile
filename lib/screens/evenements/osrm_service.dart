import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Itinéraire calculé : distance, durée et tracé (liste de points).
class RouteResult {
  final double distanceMeters;
  final double durationSeconds;
  final List<LatLng> points;
  const RouteResult({required this.distanceMeters, required this.durationSeconds, required this.points});
}

enum RouteError { timeout, noConnection, httpError, noRoute, invalidResponse }

/// Réponse : succès ou échec typé (« sealed » : switch exhaustif).
sealed class RouteResponse {
  const RouteResponse();
}

class RouteSuccess extends RouteResponse {
  final RouteResult route;
  const RouteSuccess(this.route);
}

class RouteFailure extends RouteResponse {
  final RouteError error;
  final String message; // en français, prêt à afficher
  const RouteFailure(this.error, this.message);
}

/// Calcul d'itinéraire gratuit avec l'API REST publique d'OSRM (Open Source
/// Routing Machine), sans clé, sur le même modèle que PhotonService et OpenMeteoService.
///
/// HONNÊTETÉ : router.project-osrm.org est un serveur de DÉMONSTRATION,
/// prévu pour un usage léger (au plus 1 requête par seconde, sans garantie
/// de disponibilité), et il ne calcule que des trajets EN VOITURE (profil
/// « driving »). Le temps à pied affiché à côté est une simple estimation
/// locale (5 km/h), pas un vrai itinéraire piéton.
///
/// VIE PRIVÉE : la position de l'utilisateur et celle du lieu sont envoyées
/// à ce serveur pour calculer le trajet ; rien d'autre.
class OsrmService {
  static final OsrmService instance = OsrmService();

  static const String host = 'router.project-osrm.org';
  static const String userAgent = 'CampusConnect/1.0 (com.esprit.campusconnect; projet etudiant ESPRIT)';

  final http.Client _client;
  final Duration timeout;
  final Duration minInterval;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _sleep;

  OsrmService({
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
    this.minInterval = const Duration(seconds: 1),
    DateTime Function()? now,
    Future<void> Function(Duration)? sleep,
  })  : _client = client ?? http.Client(),
        _now = now ?? DateTime.now,
        _sleep = sleep ?? ((d) => Future<void>.delayed(d));

  DateTime? _lastRequestAt;
  Future<void> _gate = Future.value();

  /// Au plus une requête par seconde, même si l'utilisateur tape « Réessayer » vite.
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

  /// Trajet en voiture de [from] à [to]. Ne lève jamais d'exception.
  Future<RouteResponse> route(LatLng from, LatLng to) async {
    await _waitTurn();
    // Attention à l'ordre : OSRM attend « longitude,latitude ».
    final uri = Uri.https(
      host,
      '/route/v1/driving/${from.longitude},${from.latitude};${to.longitude},${to.latitude}',
      {'overview': 'full', 'geometries': 'geojson'},
    );

    final http.Response response;
    try {
      response = await _client.get(uri, headers: {'User-Agent': userAgent}).timeout(timeout);
    } on TimeoutException {
      return const RouteFailure(RouteError.timeout, "Le service d'itinéraire ne répond pas.");
    } on SocketException {
      return const RouteFailure(RouteError.noConnection, "Pas de connexion au service d'itinéraire.");
    } on http.ClientException {
      return const RouteFailure(RouteError.noConnection, "Pas de connexion au service d'itinéraire.");
    }

    try {
      final decoded = json.decode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) throw const FormatException('objet attendu');
      final code = decoded['code'];
      // OSRM répond « NoRoute » (parfois avec un statut HTTP 400) quand aucun
      // trajet routier ne relie les deux points.
      if (code == 'NoRoute' || code == 'NoSegment') {
        return const RouteFailure(RouteError.noRoute, "Aucun itinéraire routier trouvé jusqu'à ce lieu.");
      }
      if (response.statusCode != 200) {
        return RouteFailure(RouteError.httpError, "Service d'itinéraire indisponible (HTTP ${response.statusCode}).");
      }
      final routes = decoded['routes'];
      if (code != 'Ok' || routes is! List || routes.isEmpty) {
        return const RouteFailure(RouteError.noRoute, "Aucun itinéraire routier trouvé jusqu'à ce lieu.");
      }
      final first = routes.first as Map<String, dynamic>;
      final coordinates = (first['geometry'] as Map<String, dynamic>)['coordinates'] as List;
      final points = [
        // GeoJSON aussi : [longitude, latitude].
        for (final c in coordinates) LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
      ];
      return RouteSuccess(RouteResult(
        distanceMeters: (first['distance'] as num).toDouble(),
        durationSeconds: (first['duration'] as num).toDouble(),
        points: points,
      ));
    } on FormatException {
      return response.statusCode != 200
          ? RouteFailure(RouteError.httpError, "Service d'itinéraire indisponible (HTTP ${response.statusCode}).")
          : const RouteFailure(RouteError.invalidResponse, "Réponse du service d'itinéraire illisible.");
    } on TypeError {
      return const RouteFailure(RouteError.invalidResponse, "Réponse du service d'itinéraire illisible.");
    }
  }
}
