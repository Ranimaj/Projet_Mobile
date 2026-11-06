import 'package:geolocator/geolocator.dart';

import '../core/utils/geo.dart';

/// Raison pour laquelle la position n'a pas pu être obtenue.
enum LocationFailure { serviceDisabled, denied, deniedForever, unavailable }

/// Résultat d'une demande de position : un point, ou une raison d'échec.
class LocationResult {
  final GeoPoint2? point;
  final LocationFailure? failure;
  const LocationResult.found(GeoPoint2 this.point) : failure = null;
  const LocationResult.failed(LocationFailure this.failure) : point = null;

  String get message => switch (failure) {
        LocationFailure.serviceDisabled => 'Active la localisation du téléphone.',
        LocationFailure.denied => 'Autorise l\'accès à la position pour filtrer par distance.',
        LocationFailure.deniedForever =>
          'Accès à la position refusé : autorise-le dans les réglages de l\'application.',
        LocationFailure.unavailable => 'Position introuvable pour le moment.',
        null => '',
      };
}

/// Fonction qui renvoie la position courante (injectable dans les tests).
typedef LocationLookup = Future<LocationResult> Function();

/// Position actuelle via geolocator, en demandant la permission au besoin.
Future<LocationResult> currentLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationResult.failed(LocationFailure.serviceDisabled);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return const LocationResult.failed(LocationFailure.denied);
    }
    if (permission == LocationPermission.deniedForever) {
      return const LocationResult.failed(LocationFailure.deniedForever);
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return LocationResult.found(GeoPoint2(pos.latitude, pos.longitude));
  } catch (_) {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return LocationResult.found(GeoPoint2(last.latitude, last.longitude));
    } catch (_) {}
    return const LocationResult.failed(LocationFailure.unavailable);
  }
}
