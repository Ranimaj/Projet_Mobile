import 'dart:convert';
import 'package:campusconnect/models/event_model.dart';
import 'package:campusconnect/screens/evenements/open_meteo_service.dart';
import 'package:campusconnect/screens/evenements/weather_rules.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  // Début de l'événement : 20 octobre 2026, 14 h 30 UTC → on garde l'heure de 14 h.
  final start = DateTime.utc(2026, 10, 20, 14, 30);

  http.Response jsonResponse(Object body, [int status = 200]) => http.Response.bytes(
        utf8.encode(json.encode(body)),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  Map<String, dynamic> forecast({double temp14 = 23.6, int code14 = 0}) => {
        'hourly': {
          'time': ['2026-10-20T13:00', '2026-10-20T14:00', '2026-10-20T15:00'],
          'temperature_2m': [22.1, temp14, 24.0],
          'weather_code': [1, code14, 3],
        },
      };

  OpenMeteoService service(MockClient client, {Duration timeout = const Duration(seconds: 10)}) =>
      OpenMeteoService(client: client, timeout: timeout);

  group('OpenMeteoService', () {
    test('réponse valide : garde l’heure du début (14 h)', () async {
      final r = await service(MockClient((_) async => jsonResponse(forecast(temp14: 23.6, code14: 61))))
          .forecastAt(36.8987, 10.1897, start);
      expect(r, isA<WeatherSuccess>());
      final w = (r as WeatherSuccess).weather;
      expect(w.temperatureC, 23.6);
      expect(w.weatherCode, 61);
      expect(w.timeUtc, DateTime.utc(2026, 10, 20, 14));
    });

    test('requête : coordonnées, variables horaires, GMT, jour de l’événement', () async {
      late http.Request sent;
      await service(MockClient((req) async {
        sent = req;
        return jsonResponse(forecast());
      })).forecastAt(36.8987, 10.1897, start);
      expect(sent.url.host, 'api.open-meteo.com');
      expect(sent.url.path, '/v1/forecast');
      expect(sent.url.queryParameters, {
        'latitude': '36.8987',
        'longitude': '10.1897',
        'hourly': 'temperature_2m,weather_code',
        'timezone': 'GMT',
        'start_date': '2026-10-20',
        'end_date': '2026-10-20',
      });
    });

    test('heure absente de la réponse : « noData »', () async {
      final r = await service(MockClient((_) async => jsonResponse({
            'hourly': {
              'time': ['2026-10-20T08:00'],
              'temperature_2m': [18.0],
              'weather_code': [0],
            },
          }))).forecastAt(36.8987, 10.1897, start);
      expect((r as WeatherFailure).error, WeatherError.noData);
    });

    test('valeur nulle pour l’heure : « noData »', () async {
      final body = <String, dynamic>{
        'hourly': <String, dynamic>{
          'time': ['2026-10-20T13:00', '2026-10-20T14:00', '2026-10-20T15:00'],
          'temperature_2m': <double?>[22.1, null, 24.0],
          'weather_code': [1, 0, 3],
        },
      };
      final r = await service(MockClient((_) async => jsonResponse(body))).forecastAt(36.8987, 10.1897, start);
      expect((r as WeatherFailure).error, WeatherError.noData);
    });

    test('HTTP 500 : échec typé', () async {
      final r = await service(MockClient((_) async => http.Response('erreur', 500))).forecastAt(36.9, 10.2, start);
      expect((r as WeatherFailure).error, WeatherError.httpError);
    });

    test('délai dépassé : « timeout »', () async {
      final slow = MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return jsonResponse(forecast());
      });
      final r = await service(slow, timeout: const Duration(milliseconds: 50)).forecastAt(36.9, 10.2, start);
      expect((r as WeatherFailure).error, WeatherError.timeout);
    });

    test('pas de connexion : « noConnection »', () async {
      final r = await service(MockClient((_) async => throw http.ClientException('coupé'))).forecastAt(36.9, 10.2, start);
      expect((r as WeatherFailure).error, WeatherError.noConnection);
    });

    test('JSON mal formé : « invalidResponse »', () async {
      final r = await service(MockClient((_) async => http.Response('{pas du json', 200))).forecastAt(36.9, 10.2, start);
      expect((r as WeatherFailure).error, WeatherError.invalidResponse);
    });

    test('structure inattendue : « invalidResponse »', () async {
      final r = await service(MockClient((_) async => jsonResponse({'hourly': 'rien'}))).forecastAt(36.9, 10.2, start);
      expect((r as WeatherFailure).error, WeatherError.invalidResponse);
    });

    test('cache : même lieu et même heure → un seul appel', () async {
      var calls = 0;
      final s = service(MockClient((_) async {
        calls++;
        return jsonResponse(forecast());
      }));
      await s.forecastAt(36.8987, 10.1897, start);
      await s.forecastAt(36.8987, 10.1897, start.add(const Duration(minutes: 10))); // même heure
      expect(calls, 1);
    });
  });

  group('WeatherRules.describe (code WMO → icône et libellé)', () {
    test('ciel dégagé, nuageux, couvert', () {
      expect(WeatherRules.describe(0), (icon: Icons.wb_sunny_outlined, label: 'Ciel dégagé'));
      expect(WeatherRules.describe(2).label, 'Peu nuageux');
      expect(WeatherRules.describe(3).label, 'Couvert');
    });
    test('brouillard, bruine, pluie, neige, averses, orage', () {
      expect(WeatherRules.describe(45).label, 'Brouillard');
      expect(WeatherRules.describe(53).label, 'Bruine');
      expect(WeatherRules.describe(63).label, 'Pluie');
      expect(WeatherRules.describe(73).label, 'Neige');
      expect(WeatherRules.describe(81).label, 'Averses');
      expect(WeatherRules.describe(95).icon, Icons.thunderstorm_outlined);
    });
    test('code inconnu : libellé prudent', () {
      expect(WeatherRules.describe(42).label, 'Météo incertaine');
    });
    test('température arrondie', () {
      expect(WeatherRules.formatTemperature(23.6), '24 °C');
      expect(WeatherRules.formatTemperature(-0.4), '0 °C');
    });
  });

  group('WeatherRules.shouldShowWeather', () {
    final now = DateTime(2026, 10, 19, 10, 0);
    EventModel ev({DateTime? startAt, bool located = true}) => EventModel(
          id: 'e',
          organizerId: 'org',
          organizerName: 'Club',
          title: 'Titre',
          description: 'Description',
          category: 'Sport',
          startDate: startAt ?? now.add(const Duration(days: 2)),
          location: 'Stade',
          latitude: located ? 36.9 : null,
          longitude: located ? 10.2 : null,
        );

    test('localisé, dans 2 jours : affichée', () => expect(WeatherRules.shouldShowWeather(ev(), now), isTrue));
    test('non localisé : cachée', () => expect(WeatherRules.shouldShowWeather(ev(located: false), now), isFalse));
    test('déjà commencé : cachée', () {
      expect(WeatherRules.shouldShowWeather(ev(startAt: now.subtract(const Duration(minutes: 1))), now), isFalse);
    });
    test('dans 13 jours : affichée ; dans 14 jours ou plus : cachée', () {
      expect(WeatherRules.shouldShowWeather(ev(startAt: now.add(const Duration(days: 13))), now), isTrue);
      expect(WeatherRules.shouldShowWeather(ev(startAt: now.add(const Duration(days: 14))), now), isFalse);
      expect(WeatherRules.shouldShowWeather(ev(startAt: now.add(const Duration(days: 20))), now), isFalse);
    });
  });
}
