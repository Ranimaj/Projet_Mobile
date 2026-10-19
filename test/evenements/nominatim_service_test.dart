import 'dart:convert';
import 'package:campusconnect/screens/evenements/nominatim_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Tests sans réseau : MockClient remplace le vrai serveur Nominatim, et
/// l'horloge / l'attente sont simulées (aucune vraie seconde perdue).
void main() {
  const esprit = [
    {'lat': '36.8987', 'lon': '10.1897', 'display_name': 'ESPRIT, Ghazela, Ariana, Tunisie'},
  ];

  http.Response jsonResponse(Object body, [int status = 200]) => http.Response.bytes(
        utf8.encode(json.encode(body)),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  NominatimService service(MockClient client, {Duration timeout = const Duration(seconds: 10)}) =>
      NominatimService(client: client, timeout: timeout, sleep: (_) async {});

  test('réponse valide : coordonnées et nom', () async {
    final r = await service(MockClient((_) async => jsonResponse(esprit))).geocode('ESPRIT Ghazela');
    expect(r, isA<GeocodeSuccess>());
    final ok = (r as GeocodeSuccess).result;
    expect(ok.lat, closeTo(36.8987, 1e-9));
    expect(ok.lng, closeTo(10.1897, 1e-9));
    expect(ok.displayName, contains('Ghazela'));
  });

  test('requête : paramètres, Tunisie par défaut et User-Agent', () async {
    late http.Request sent;
    await service(MockClient((req) async {
      sent = req;
      return jsonResponse(esprit);
    })).geocode('  ESPRIT   Ghazela ');
    expect(sent.url.host, 'nominatim.openstreetmap.org');
    expect(sent.url.path, '/search');
    expect(sent.url.queryParameters, {
      'q': 'ESPRIT Ghazela',
      'format': 'jsonv2',
      'limit': '1',
      'countrycodes': 'tn',
    });
    expect(sent.headers['User-Agent'], contains('com.esprit.campusconnect'));
  });

  test('countryCodes modifiable, ou null pour le monde entier', () async {
    final urls = <Uri>[];
    final s = service(MockClient((req) async {
      urls.add(req.url);
      return jsonResponse(esprit);
    }));
    await s.geocode('Paris', countryCodes: 'fr');
    await s.geocode('Tokyo', countryCodes: null);
    expect(urls[0].queryParameters['countrycodes'], 'fr');
    expect(urls[1].queryParameters.containsKey('countrycodes'), isFalse);
  });

  test('liste vide : « Lieu introuvable sur la carte »', () async {
    final r = await service(MockClient((_) async => jsonResponse([]))).geocode('zzzzqq');
    expect(r, isA<GeocodeFailure>());
    expect((r as GeocodeFailure).error, GeocodeError.notFound);
    expect(r.message, 'Lieu introuvable sur la carte');
  });

  test('HTTP 500 : échec typé, pas de plantage', () async {
    final r = await service(MockClient((_) async => http.Response('erreur', 500))).geocode('Tunis');
    expect((r as GeocodeFailure).error, GeocodeError.httpError);
    expect(r.message, contains('500'));
  });

  test('délai dépassé : échec « timeout »', () async {
    final slow = MockClient((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return jsonResponse(esprit);
    });
    final r = await service(slow, timeout: const Duration(milliseconds: 50)).geocode('Tunis');
    expect((r as GeocodeFailure).error, GeocodeError.timeout);
  });

  test('pas de connexion : échec « noConnection »', () async {
    final r = await service(MockClient((_) async => throw http.ClientException('réseau coupé'))).geocode('Tunis');
    expect((r as GeocodeFailure).error, GeocodeError.noConnection);
  });

  test('JSON mal formé : échec « invalidResponse »', () async {
    final r = await service(MockClient((_) async => http.Response('{pas du json', 200))).geocode('Tunis');
    expect((r as GeocodeFailure).error, GeocodeError.invalidResponse);
  });

  test('JSON valide mais pas une liste : « invalidResponse »', () async {
    final r = await service(MockClient((_) async => jsonResponse({'erreur': 'x'}))).geocode('Tunis');
    expect((r as GeocodeFailure).error, GeocodeError.invalidResponse);
  });

  test('lieu vide : refusé sans appel réseau', () async {
    var calls = 0;
    final r = await service(MockClient((_) async {
      calls++;
      return jsonResponse(esprit);
    })).geocode('   ');
    expect((r as GeocodeFailure).error, GeocodeError.emptyQuery);
    expect(calls, 0);
  });

  test('cache : la même requête n’appelle le serveur qu’une fois', () async {
    var calls = 0;
    final s = service(MockClient((_) async {
      calls++;
      return jsonResponse(esprit);
    }));
    await s.geocode('ESPRIT Ghazela');
    await s.geocode('esprit   ghazela'); // même requête normalisée
    expect(calls, 1);
  });

  test('pas de cache pour une panne : le prochain essai rappelle le serveur', () async {
    var calls = 0;
    final s = service(MockClient((_) async {
      calls++;
      return calls == 1 ? http.Response('erreur', 503) : jsonResponse(esprit);
    }));
    expect(await s.geocode('Tunis'), isA<GeocodeFailure>());
    expect(await s.geocode('Tunis'), isA<GeocodeSuccess>());
    expect(calls, 2);
  });

  test('throttle : au moins 1 seconde entre deux requêtes', () async {
    var clock = DateTime(2026, 10, 19, 10, 0, 0);
    final waits = <Duration>[];
    final s = NominatimService(
      client: MockClient((_) async => jsonResponse(esprit)),
      now: () => clock,
      sleep: (d) async {
        waits.add(d);
        clock = clock.add(d);
      },
    );
    await s.geocode('Lieu A');
    clock = clock.add(const Duration(milliseconds: 300)); // 0,3 s plus tard
    await s.geocode('Lieu B');
    expect(waits, [const Duration(milliseconds: 700)]); // attend le reste de la seconde
    clock = clock.add(const Duration(seconds: 2));
    await s.geocode('Lieu C');
    expect(waits.length, 1); // déjà plus d'une seconde : pas d'attente
  });
}
