/// Calculs PURS de l'itinéraire (formatage, estimation à pied, lien Google
/// Maps) : aucune dépendance au réseau ni au GPS, donc testables.
class ItineraryRules {
  ItineraryRules._();

  /// Vitesse de marche utilisée pour l'estimation : 5 km/h.
  static const double walkingSpeedKmh = 5;

  /// « 850 m » sous 1 km (arrondi à 10 m), sinon « 12,4 km » (virgule française).
  static String formatDistance(double meters) {
    if (meters < 1000) {
      final rounded = (meters / 10).round() * 10;
      return '${rounded < 10 ? 10 : rounded} m';
    }
    final km = (meters / 100).round() / 10; // une décimale
    final text = km == km.roundToDouble() ? km.toStringAsFixed(0) : km.toStringAsFixed(1);
    return '${text.replaceAll('.', ',')} km';
  }

  /// « 1 min » au minimum, « 18 min », « 1 h », « 1 h 05 ».
  static String formatDuration(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 1) return '1 min';
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '$h h' : '$h h ${m.toString().padLeft(2, '0')}';
  }

  /// Temps de marche ESTIMÉ (secondes) à 5 km/h sur la distance de la
  /// route : ce n'est pas un calcul d'itinéraire piéton.
  static double walkingSeconds(double meters) => meters / (walkingSpeedKmh * 1000 / 3600);

  /// Ligne du panneau : « 12,4 km · 18 min en voiture ».
  static String drivingSummary(double meters, double seconds) =>
      '${formatDistance(meters)} · ${formatDuration(seconds)} en voiture';

  /// Ligne d'estimation à pied : « ≈ 2 h 29 à pied (estimation) ».
  static String walkingSummary(double meters) => '≈ ${formatDuration(walkingSeconds(meters))} à pied (estimation)';

  /// Lien d'itinéraire Google Maps (sans clé). Sans point de départ : Google
  /// Maps utilise lui-même la position actuelle du téléphone.
  static Uri googleMapsDirections(double lat, double lng) =>
      Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
}
