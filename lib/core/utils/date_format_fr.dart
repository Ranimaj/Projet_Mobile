import 'package:intl/intl.dart';

/// "il y a 5 min", "hier", puis date complète au-delà d'une semaine.
/// (nécessite `initializeDateFormatting('fr_FR')` — fait dans main.dart)
String relativeDateFr(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.isNegative || diff.inMinutes < 1) return "À l'instant";
  if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
  if (diff.inDays == 1) return 'hier';
  if (diff.inDays < 7) return 'il y a ${diff.inDays} j';
  return DateFormat('d MMM yyyy', 'fr_FR').format(date);
}
