import 'package:campusconnect/screens/evenements/itinerary_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('distance', () {
    test('moins d’un km : en mètres, arrondi à 10 m', () {
      expect(ItineraryRules.formatDistance(847), '850 m');
      expect(ItineraryRules.formatDistance(3), '10 m');
    });
    test('à partir d’un km : une décimale, virgule française', () {
      expect(ItineraryRules.formatDistance(12430), '12,4 km');
      expect(ItineraryRules.formatDistance(1000), '1 km');
      expect(ItineraryRules.formatDistance(1049), '1 km');
      expect(ItineraryRules.formatDistance(1050), '1,1 km');
    });
  });

  group('durée', () {
    test('minimum 1 min', () => expect(ItineraryRules.formatDuration(20), '1 min'));
    test('minutes', () => expect(ItineraryRules.formatDuration(1083), '18 min'));
    test('heures pleines et heures + minutes', () {
      expect(ItineraryRules.formatDuration(3600), '1 h');
      expect(ItineraryRules.formatDuration(3900), '1 h 05');
      expect(ItineraryRules.formatDuration(8940), '2 h 29');
    });
  });

  group('marche (estimation à 5 km/h)', () {
    test('5 km = 1 heure', () => expect(ItineraryRules.walkingSeconds(5000), closeTo(3600, 1e-6)));
    test('12,4 km ≈ 2 h 29', () {
      expect(ItineraryRules.walkingSummary(12430), '≈ 2 h 29 à pied (estimation)');
    });
  });

  test('ligne voiture du panneau', () {
    expect(ItineraryRules.drivingSummary(12430, 1083), '12,4 km · 18 min en voiture');
  });

  test('lien Google Maps : destination sans point de départ, sans clé', () {
    final uri = ItineraryRules.googleMapsDirections(36.8987, 10.1897);
    expect(uri.toString(), 'https://www.google.com/maps/dir/?api=1&destination=36.8987,10.1897');
    expect(uri.queryParameters['api'], '1');
    expect(uri.queryParameters['destination'], '36.8987,10.1897');
  });
}
