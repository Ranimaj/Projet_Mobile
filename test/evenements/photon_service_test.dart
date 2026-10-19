import 'dart:convert';
import 'package:campusconnect/screens/evenements/photon_service.dart';
import 'package:campusconnect/screens/evenements/place_rules.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Tests sans réseau : MockClient remplace le serveur Photon.
void main() {
  http.Response jsonResponse(Object body, [int status = 200]) => http.Response.bytes(
        utf8.encode(json.encode(body)),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  Map<String, dynamic> feature({
    required double lng,
    required double lat,
    String? name,
    String? street,
    String? district,
    String? city,
    String country = 'Tunisie',
    String countrycode = 'TN',
  }) =>
      {
        'type': 'Feature',
        'geometry': {'type': 'Point', 'coordinates': [lng, lat]},
        'properties': {
          if (name != null) 'name': name,
          if (street != null) 'street': street,
          if (district != null) 'district': district,
          if (city != null) 'city': city,
          'country': country,
          'countrycode': countrycode,
        },
      };

  Map<String, dynamic> collection(List<Map<String, dynamic>> features) =>
      {'type': 'FeatureCollection', 'features': features};

  PhotonService service(MockClient client, {Duration timeout = const Duration(seconds: 8)}) =>
      PhotonService(client: client, timeout: timeout, sleep: (_) async {});

  group('PhotonService', () {
    test('suggestion valide : [lng, lat] remis dans l’ordre lat, lng', () async {
      final r = await service(MockClient((_) async => jsonResponse(collection([
            feature(lng: 10.1956, lat: 36.8625, name: 'Ariana', city: 'Ariana'),
          ])))).search('ariana');
      final list = (r as PhotonSuccess).suggestions;
      expect(list.length, 1);
      expect(list.first.latitude, 36.8625);
      expect(list.first.longitude, 10.1956);
      expect(list.first.name, 'Ariana');
      expect(list.first.label, 'Ariana, Tunisie'); // « Ariana » (ville) non répété
      expect(list.first.secondary, 'Tunisie');
    });

    test('requête : paramètres, point fixe Tunis, User-Agent', () async {
      late http.Request sent;
      await service(MockClient((req) async {
        sent = req;
        return jsonResponse(collection([]));
      })).search('  esprit ghazela ');
      expect(sent.url.host, 'photon.komoot.io');
      expect(sent.url.path, '/api/');
      expect(sent.url.queryParameters, {
        'q': 'esprit ghazela',
        'limit': '5',
        'lang': 'fr',
        'lat': '36.8065',
        'lon': '10.1815',
      });
      expect(sent.headers['User-Agent'], contains('com.esprit.campusconnect'));
    });

    test('seulement la Tunisie (countrycode TN, sans tenir compte de la casse)', () async {
      final r = await service(MockClient((_) async => jsonResponse(collection([
            feature(lng: 2.35, lat: 48.85, name: 'Ariana Café', city: 'Paris', country: 'France', countrycode: 'FR'),
            feature(lng: 10.19, lat: 36.86, name: 'Ariana', city: 'Ariana', countrycode: 'tn'),
          ])))).search('ariana');
      final list = (r as PhotonSuccess).suggestions;
      expect(list.map((s) => s.name), ['Ariana']);
    });

    test('doublons retirés (même libellé)', () async {
      final r = await service(MockClient((_) async => jsonResponse(collection([
            feature(lng: 10.19, lat: 36.86, name: 'Ariana', city: 'Ariana'),
            feature(lng: 10.20, lat: 36.87, name: 'Ariana', city: 'ariana'), // même libellé
          ])))).search('ariana');
      expect((r as PhotonSuccess).suggestions.length, 1);
    });

    test('au plus 5 suggestions', () async {
      final r = await service(MockClient((_) async => jsonResponse(collection([
            for (var i = 0; i < 8; i++) feature(lng: 10.1 + i / 100, lat: 36.8, name: 'Lieu $i', city: 'Tunis'),
          ])))).search('lieu');
      expect((r as PhotonSuccess).suggestions.length, 5);
    });

    test('rue, sinon quartier, dans la ligne grise', () async {
      final r = await service(MockClient((_) async => jsonResponse(collection([
            feature(lng: 10.18, lat: 36.89, name: 'ESPRIT', street: 'Rue de l’Énergie', city: 'Ariana'),
            feature(lng: 10.17, lat: 36.80, name: 'Café', district: 'Lafayette', city: 'Tunis'),
          ])))).search('esp');
      final list = (r as PhotonSuccess).suggestions;
      expect(list[0].secondary, 'Rue de l’Énergie, Ariana, Tunisie');
      expect(list[1].secondary, 'Lafayette, Tunis, Tunisie');
    });

    test('aucun résultat : succès avec liste vide (pas une erreur)', () async {
      final r = await service(MockClient((_) async => jsonResponse(collection([])))).search('zzzzqq');
      expect((r as PhotonSuccess).suggestions, isEmpty);
    });

    test('texte vide : aucune requête', () async {
      var calls = 0;
      final r = await service(MockClient((_) async {
        calls++;
        return jsonResponse(collection([]));
      })).search('   ');
      expect(r, isA<PhotonSuccess>());
      expect(calls, 0);
    });

    test('HTTP 500 : échec typé', () async {
      final r = await service(MockClient((_) async => http.Response('erreur', 500))).search('ariana');
      expect((r as PhotonFailure).error, PhotonError.httpError);
    });

    test('délai dépassé : « timeout »', () async {
      final slow = MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return jsonResponse(collection([]));
      });
      final r = await service(slow, timeout: const Duration(milliseconds: 50)).search('ariana');
      expect((r as PhotonFailure).error, PhotonError.timeout);
    });

    test('pas de connexion : « noConnection »', () async {
      final r = await service(MockClient((_) async => throw http.ClientException('coupé'))).search('ariana');
      expect((r as PhotonFailure).error, PhotonError.noConnection);
    });

    test('JSON mal formé : « invalidResponse »', () async {
      final r = await service(MockClient((_) async => http.Response('{pas du json', 200))).search('ariana');
      expect((r as PhotonFailure).error, PhotonError.invalidResponse);
    });

    test('au plus 1 requête toutes les 500 ms', () async {
      var clock = DateTime(2026, 10, 19, 10, 0, 0);
      final waits = <Duration>[];
      final s = PhotonService(
        client: MockClient((_) async => jsonResponse(collection([]))),
        now: () => clock,
        sleep: (d) async {
          waits.add(d);
          clock = clock.add(d);
        },
      );
      await s.search('ari');
      clock = clock.add(const Duration(milliseconds: 200));
      await s.search('aria');
      expect(waits, [const Duration(milliseconds: 300)]);
    });
  });

  group('PlaceRules.formatSuggestionLabel', () {
    test('toutes les parties, dans l’ordre', () {
      expect(
          PlaceRules.formatSuggestionLabel(
              name: 'ESPRIT', street: 'Rue X', district: 'Ghazela', city: 'Ariana', country: 'Tunisie'),
          'ESPRIT, Rue X, Ariana, Tunisie'); // la rue passe avant le quartier
    });
    test('pas de rue : le quartier à la place', () {
      expect(PlaceRules.formatSuggestionLabel(name: 'Café', district: 'Lafayette', city: 'Tunis', country: 'Tunisie'),
          'Café, Lafayette, Tunis, Tunisie');
    });
    test('parties manquantes ou vides ignorées', () {
      expect(PlaceRules.formatSuggestionLabel(name: 'Stade', street: '  ', city: null, country: 'Tunisie'),
          'Stade, Tunisie');
    });
    test('doublons retirés, sans tenir compte des majuscules', () {
      expect(PlaceRules.formatSuggestionLabel(name: 'Ariana', city: 'ARIANA', country: 'Tunisie'), 'Ariana, Tunisie');
    });
    test('espaces autour retirés', () {
      expect(PlaceRules.formatSuggestionLabel(name: '  Sousse ', country: ' Tunisie '), 'Sousse, Tunisie');
    });
    test('tout vide : libellé vide', () {
      expect(PlaceRules.formatSuggestionLabel(), '');
      expect(PlaceRules.formatSuggestionLabel(name: '', city: ' '), '');
    });
  });
}
