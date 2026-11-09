/// Libellés de dates en français, partagés par l'accueil et ses statistiques.
abstract final class FrDates {
  static const days = [
    'Lundi',
    'Mardi',
    'Mercredi',
    'Jeudi',
    'Vendredi',
    'Samedi',
    'Dimanche'
  ];
  static const dayShort = ['LUN', 'MAR', 'MER', 'JEU', 'VEN', 'SAM', 'DIM'];
  static const months = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre'
  ];
  static const monthShort = [
    'JAN',
    'FÉV',
    'MAR',
    'AVR',
    'MAI',
    'JUIN',
    'JUIL',
    'AOÛ',
    'SEP',
    'OCT',
    'NOV',
    'DÉC'
  ];
  static String hhmm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// « 9 nov. à 14:32 » ; « à l'instant » quand la date n'est pas encore
  /// connue (heure du serveur en attente).
  static String shortDateTime(DateTime? d) {
    if (d == null) return 'à l\'instant';
    final month = months[d.month - 1];
    final short = month.length <= 4 ? month : '${month.substring(0, 3)}.';
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day} $short à $hh:$mm';
  }
}
