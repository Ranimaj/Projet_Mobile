import 'package:flutter/material.dart';
import '../../models/event_model.dart';

/// Règles PURES de la météo (testables sans réseau).
class WeatherRules {
  WeatherRules._();

  /// Limite des prévisions qu'on affiche : 14 jours.
  static const Duration forecastHorizon = Duration(days: 14);

  /// Afficher la météo ? Seulement si le lieu est localisé et que
  /// l'événement commence dans le futur, dans les 14 prochains jours.
  static bool shouldShowWeather(EventModel event, DateTime now) =>
      event.latitude != null &&
      event.longitude != null &&
      event.startDate.isAfter(now) &&
      event.startDate.isBefore(now.add(forecastHorizon));

  /// Code météo WMO (utilisé par Open-Meteo) → icône et libellé court.
  static ({IconData icon, String label}) describe(int code) {
    switch (code) {
      case 0:
        return (icon: Icons.wb_sunny_outlined, label: 'Ciel dégagé');
      case 1:
      case 2:
        return (icon: Icons.wb_cloudy_outlined, label: 'Peu nuageux');
      case 3:
        return (icon: Icons.cloud_outlined, label: 'Couvert');
      case 45:
      case 48:
        return (icon: Icons.foggy, label: 'Brouillard');
      case 51:
      case 53:
      case 55:
      case 56:
      case 57:
        return (icon: Icons.grain, label: 'Bruine');
      case 61:
      case 63:
      case 65:
      case 66:
      case 67:
        return (icon: Icons.water_drop_outlined, label: 'Pluie');
      case 71:
      case 73:
      case 75:
      case 77:
      case 85:
      case 86:
        return (icon: Icons.ac_unit, label: 'Neige');
      case 80:
      case 81:
      case 82:
        return (icon: Icons.umbrella_outlined, label: 'Averses');
      case 95:
      case 96:
      case 99:
        return (icon: Icons.thunderstorm_outlined, label: 'Orage');
      default:
        return (icon: Icons.help_outline, label: 'Météo incertaine');
    }
  }

  /// « 24 °C » (arrondi au degré).
  static String formatTemperature(double celsius) => '${celsius.round()} °C';
}
