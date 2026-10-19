import 'dart:convert';
import 'package:campusconnect/screens/evenements/osrm_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

/// Tests sans réseau : MockClient remplace le serveur OSRM.
void main() {
  const me = LatLng(36.8065, 10.1815); // Tunis centre
  const esprit = LatLng(36.8987, 10.1897); // ESPRIT Ghazela

  http.Response jsonResponse(Object body, [int status = 200]) => http.Response.bytes(
        utf8.encode(json.encode(body)),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  final okBody = {
    'code': 'Ok',
    'routes': [
      {
        'distance': 12430.5,
        'duration': 1083.2,
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            [10.1815, 36.8065],
            [10.1850, 36.8500],
            [10.1897, 36.8987],
          ],
        },
      }
    ],
  };

  OsrmService service(MockClient client, {Duration timeout = const Duration(seconds: 10)}) =>
      OsrmService(client: client, timeout: timeout, sleep: (_) async {});

  test('trajet valide : distance, durée et points (lat/lng remis dans le bon ordre)', () async {
    final r = await service(MockClient((_) async => jsonResponse(okBody))).route(me, esprit);
    expect(r, isA<RouteSuccess>());
    final route = (r as RouteSuccess).route;
    expect(route.distanceMeters, 12430.5);
    expect(route.durationSeconds, 1083.2);
    expect(route.points.length, 3);
    expect(route.points.first, const LatLng(36.8065, 10.1815));
    expect(route.points.last, const LatLng(36.8987, 10.1897));
  });

  test('requête : longitude,latitude dans l’URL, geojson et User-Agent', () async {
    late http.Request sent;
    await service(MockClient((req) async {
      sent = req;
      return jsonResponse(okBody);
    })).route(me, esprit);
    expect(sent.url.host, 'router.project-osrm.org');
    expect(sent.url.path, '/route/v1/driving/10.1815,36.8065;10.1897,36.8987');
    expect(sent.url.queryParameters, {'overview': 'full', 'geometries': 'geojson'});
    expect(sent.headers['User-Agent'], contains('com.esprit.campusconnect'));
  });

  test('aucun trajet (code NoRoute, HTTP 400) : échec « noRoute »', () async {
    final r = await service(MockClient((_) async => jsonResponse({'code': 'NoRoute', 'routes': []}, 400)))
        .route(me, esprit);
    expect((r as RouteFailure).error, RouteError.noRoute);
    expect(r.message, contains('Aucun itinéraire'));
  });

  test('liste de trajets vide : échec « noRoute »', () async {
    final r = await service(MockClient((_) async => jsonResponse({'code': 'Ok', 'routes': []}))).route(me, esprit);
    expect((r as RouteFailure).error, RouteError.noRoute);
  });

  test('HTTP 500 : échec typé, pas de plantage', () async {
    final r = await service(MockClient((_) async => http.Response('erreur', 500))).route(me, esprit);
    expect((r as RouteFailure).error, RouteError.httpError);
    expect(r.message, contains('500'));
  });

  test('délai dépassé : échec « timeout »', () async {
    final slow = MockClient((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return jsonResponse(okBody);
    });
    final r = await service(slow, timeout: const Duration(milliseconds: 50)).route(me, esprit);
    expect((r as RouteFailure).error, RouteError.timeout);
  });

  test('pas de connexion : échec « noConnection »', () async {
    final r = await service(MockClient((_) async => throw http.ClientException('réseau coupé'))).route(me, esprit);
    expect((r as RouteFailure).error, RouteError.noConnection);
  });

  test('JSON mal formé : échec « invalidResponse »', () async {
    final r = await service(MockClient((_) async => http.Response('{pas du json', 200))).route(me, esprit);
    expect((r as RouteFailure).error, RouteError.invalidResponse);
  });

  test('JSON valide mais structure inattendue : « invalidResponse »', () async {
    final r = await service(MockClient((_) async => jsonResponse({
          'code': 'Ok',
          'routes': [
            {'distance': 'beaucoup', 'duration': 10, 'geometry': {}}
          ],
        }))).route(me, esprit);
    expect((r as RouteFailure).error, RouteError.invalidResponse);
  });
}
