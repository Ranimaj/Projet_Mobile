import 'dart:math' as math;

/// Position GPS simple (latitude / longitude en degrés).
class GeoPoint2 {
  final double latitude;
  final double longitude;
  const GeoPoint2(this.latitude, this.longitude);

  @override
  bool operator ==(Object other) =>
      other is GeoPoint2 && other.latitude == latitude && other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

const double _earthRadiusKm = 6371.0;

double _rad(double deg) => deg * math.pi / 180;

/// Distance à vol d'oiseau entre deux points (formule de haversine), en km.
double distanceKm(GeoPoint2 a, GeoPoint2 b) {
  final dLat = _rad(b.latitude - a.latitude);
  final dLng = _rad(b.longitude - a.longitude);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.latitude)) * math.cos(_rad(b.latitude)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthRadiusKm * math.asin(math.min(1, math.sqrt(h)));
}

/// « 350 m », « 1,2 km », « 14 km ».
String formatDistance(double km) {
  if (km < 1) {
    final m = (km * 1000 / 10).round() * 10;
    return '${m < 10 ? 10 : m} m';
  }
  if (km < 10) return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
  return '${km.round()} km';
}
