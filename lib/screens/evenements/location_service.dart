import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

enum PositionError { serviceOff, denied, deniedForever, timeout, unknown }

/// Position de l'utilisateur, ou échec typé (« sealed » : switch exhaustif).
sealed class PositionResponse {
  const PositionResponse();
}

class PositionSuccess extends PositionResponse {
  final LatLng position;
  const PositionSuccess(this.position);
}

class PositionFailure extends PositionResponse {
  final PositionError error;
  final String message; // en français, prêt à afficher
  const PositionFailure(this.error, this.message);
}

/// Fine couche autour de geolocator : demande la permission « pendant
/// l'utilisation » si besoin, puis lit la position. Ne lève jamais
/// d'exception. Aucune localisation en arrière-plan.
class LocationService {
  LocationService._();

  static const Duration timeout = Duration(seconds: 15);

  static Future<PositionResponse> currentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const PositionFailure(PositionError.serviceOff, 'La localisation du téléphone est désactivée.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const PositionFailure(PositionError.deniedForever,
            'Localisation refusée définitivement : autorisez-la dans les réglages de l\'app.');
      }
      if (permission == LocationPermission.denied) {
        return const PositionFailure(PositionError.denied, 'Localisation refusée : itinéraire impossible.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: timeout),
      );
      return PositionSuccess(LatLng(position.latitude, position.longitude));
    } on TimeoutException {
      return const PositionFailure(PositionError.timeout, 'Position introuvable pour le moment (délai dépassé).');
    } on LocationServiceDisabledException {
      return const PositionFailure(PositionError.serviceOff, 'La localisation du téléphone est désactivée.');
    } on PermissionDeniedException {
      return const PositionFailure(PositionError.denied, 'Localisation refusée : itinéraire impossible.');
    } catch (_) {
      return const PositionFailure(PositionError.unknown, 'Impossible de lire votre position.');
    }
  }

  /// Ouvre les réglages de l'app (permission refusée définitivement).
  static Future<bool> openAppSettings() => Geolocator.openAppSettings();

  /// Ouvre les réglages de localisation du téléphone (service désactivé).
  static Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}
