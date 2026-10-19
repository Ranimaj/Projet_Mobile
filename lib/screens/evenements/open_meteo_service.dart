import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Prévision pour l'heure de début d'un événement.
class WeatherResult {
  final double temperatureC;
  final int weatherCode; // code WMO
  final DateTime timeUtc;
  const WeatherResult({required this.temperatureC, required this.weatherCode, required this.timeUtc});
}

enum WeatherError { timeout, noConnection, httpError, noData, invalidResponse }

/// Réponse : succès ou échec typé (« sealed » : switch exhaustif).
sealed class WeatherResponse {
  const WeatherResponse();
}

class WeatherSuccess extends WeatherResponse {
  final WeatherResult weather;
  const WeatherSuccess(this.weather);
}

class WeatherFailure extends WeatherResponse {
  final WeatherError error;
  final String message; // pour les journaux : l'écran cache simplement la puce
  const WeatherFailure(this.error, this.message);
}

/// Prévisions météo gratuites, sans clé, avec l'API REST Open-Meteo, sur le
/// même modèle que OsrmService.
///
/// On demande les valeurs heure par heure en temps universel (timezone=GMT)
/// pour le jour de l'événement, puis on garde l'heure de son début.
///
/// VIE PRIVÉE : seules les coordonnées du lieu de l'événement sont envoyées
/// (pas la position de l'utilisateur).
class OpenMeteoService {
  static final OpenMeteoService instance = OpenMeteoService();

  static const String host = 'api.open-meteo.com';
  static const String userAgent = 'CampusConnect/1.0 (com.esprit.campusconnect; projet etudiant ESPRIT)';

  final http.Client _client;
  final Duration timeout;

  OpenMeteoService({http.Client? client, this.timeout = const Duration(seconds: 10)})
      : _client = client ?? http.Client();

  /// Cache mémoire : la fiche se reconstruit souvent (données en direct),
  /// on ne redemande pas la même prévision.
  final Map<String, WeatherSuccess> _cache = {};

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Prévision au lieu ([lat], [lng]) pour l'heure de [start] (arrondie à
  /// l'heure inférieure). Ne lève jamais d'exception.
  Future<WeatherResponse> forecastAt(double lat, double lng, DateTime start) async {
    final u = start.toUtc();
    final hour = DateTime.utc(u.year, u.month, u.day, u.hour);
    final key = '${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}@${hour.toIso8601String()}';
    final cached = _cache[key];
    if (cached != null) return cached;

    final uri = Uri.https(host, '/v1/forecast', {
      'latitude': '$lat',
      'longitude': '$lng',
      'hourly': 'temperature_2m,weather_code',
      'timezone': 'GMT',
      'start_date': _date(hour),
      'end_date': _date(hour),
    });

    final http.Response response;
    try {
      response = await _client.get(uri, headers: {'User-Agent': userAgent}).timeout(timeout);
    } on TimeoutException {
      return const WeatherFailure(WeatherError.timeout, 'Le service météo ne répond pas.');
    } on SocketException {
      return const WeatherFailure(WeatherError.noConnection, 'Pas de connexion au service météo.');
    } on http.ClientException {
      return const WeatherFailure(WeatherError.noConnection, 'Pas de connexion au service météo.');
    }
    if (response.statusCode != 200) {
      return WeatherFailure(WeatherError.httpError, 'Service météo indisponible (HTTP ${response.statusCode}).');
    }

    try {
      final decoded = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final hourly = decoded['hourly'] as Map<String, dynamic>;
      final times = hourly['time'] as List;
      final temps = hourly['temperature_2m'] as List;
      final codes = hourly['weather_code'] as List;
      // Les heures arrivent sans « Z » (« 2026-10-20T13:00 ») : c'est du GMT.
      final index = times.indexWhere((t) => DateTime.parse('${t}Z') == hour);
      if (index < 0 || temps[index] == null || codes[index] == null) {
        return const WeatherFailure(WeatherError.noData, 'Pas de prévision pour cette heure.');
      }
      final success = WeatherSuccess(WeatherResult(
        temperatureC: (temps[index] as num).toDouble(),
        weatherCode: (codes[index] as num).toInt(),
        timeUtc: hour,
      ));
      _cache[key] = success;
      return success;
    } on FormatException {
      return const WeatherFailure(WeatherError.invalidResponse, 'Réponse du service météo illisible.');
    } on TypeError {
      return const WeatherFailure(WeatherError.invalidResponse, 'Réponse du service météo illisible.');
    }
  }
}
