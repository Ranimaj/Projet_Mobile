import 'package:flutter/painting.dart';

import '../../models/event_model.dart';
import 'event_rules.dart';
import 'event_style.dart';
import 'ticket_rules.dart';

/// Adresse web encodée dans le QR du billet, lue par docs/billet/index.html :
///
/// `<base>#<encodeComponent("CC1|eventId|uid")>?t=…&n=…&c=…&k=…&d=…&e=…&p=…&x=…`
///
/// Seul le fragment avant « ? » sert au pointage (TicketRules.parseTicketPayload).
/// Les paramètres ne sont que de l'AFFICHAGE : titre, titulaire, catégorie,
/// couleur, début et fin (ISO 8601 UTC), lieu, prix. Le fragment d'une
/// adresse n'est jamais envoyé au serveur qui héberge la page.
class TicketLink {
  TicketLink._();

  /// Longueur maximale de l'adresse : le QR reste petit et facile à scanner.
  static const int maxLength = 512;

  // Longueurs maximales (en caractères) des textes affichés par la page.
  static const int titleMax = 60;
  static const int holderMax = 40;
  static const int categoryMax = 24;
  static const int placeMax = 60;
  static const int priceMax = 16;

  /// Ordre de raccourcissement quand l'adresse dépasse [maxLength] (textes
  /// très accentués), avec la longueur minimale gardée pour chacun.
  static const List<(String, int)> _shrinkOrder = [('p', 12), ('n', 12), ('t', 16), ('c', 8)];

  /// Couleur de catégorie de l'application (bande du billet), 6 chiffres
  /// hexadécimaux sans « # ».
  static String colorHex(Color color) =>
      (color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  /// Date en ISO 8601 UTC, à la seconde (« 2026-11-10T17:00:00Z »).
  static String isoUtc(DateTime d) => d.toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d+Z$'), 'Z');

  /// [text] sans espaces autour, coupé à [max] caractères (« … » final).
  static String cut(String text, int max) {
    final runes = text.trim().runes.toList();
    if (runes.length <= max) return text.trim();
    return '${String.fromCharCodes(runes.take(max - 1)).trimRight()}…';
  }

  /// Adresse complète du billet de [uid] pour [event].
  static String build(EventModel event, String uid, String holderName,
      {String baseUrl = TicketRules.billetBaseUrl}) {
    final source = <String, (String, int)>{
      't': (event.title, titleMax),
      'n': (holderName, holderMax),
      'c': (event.category, categoryMax),
      'p': (event.location, placeMax),
    };
    final values = <String, String>{for (final e in source.entries) e.key: cut(e.value.$1, e.value.$2)};
    final fixed = <String, String>{
      'k': colorHex(EventStyle.categoryColor(event.category)),
      'd': isoUtc(event.startDate),
      'e': isoUtc(event.endDate),
      'x': cut(EventRules.priceLabel(event), priceMax),
    };
    final head = '$baseUrl#${Uri.encodeComponent(TicketRules.buildTicketPayload(event.id, uid))}';

    String compose() {
      final all = {
        't': values['t']!,
        'n': values['n']!,
        'c': values['c']!,
        'k': fixed['k']!,
        'd': fixed['d']!,
        'e': fixed['e']!,
        'p': values['p']!,
        'x': fixed['x']!,
      };
      final query = all.entries
          .where((e) => e.value.isNotEmpty)
          .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
          .join('&');
      return query.isEmpty ? head : '$head?$query';
    }

    var link = compose();
    // Trop long (textes très accentués) : on raccourcit le lieu, puis le
    // nom, le titre et la catégorie, sans descendre sous leur minimum.
    for (final (key, min) in _shrinkOrder) {
      var limit = values[key]!.runes.length;
      while (link.length > maxLength && limit > min) {
        limit--;
        values[key] = cut(source[key]!.$1, limit);
        link = compose();
      }
    }
    // Encore trop long (adresse de base très longue) : on retire les textes,
    // l'identifiant du billet reste toujours.
    for (final key in ['p', 'n', 't', 'c']) {
      if (link.length <= maxLength) break;
      values[key] = '';
      link = compose();
    }
    return link;
  }
}
