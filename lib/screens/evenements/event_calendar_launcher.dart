import 'package:add_2_calendar/add_2_calendar.dart' as cal;
import 'package:flutter/services.dart';
import '../../providers/event_provider.dart';
import 'event_calendar_sync.dart';

/// Fine couche autour du plugin add_2_calendar : convertit une
/// [CalendarEntry] (calculée par la logique pure EventCalendarSync) et ouvre
/// le calendrier du téléphone. Toute erreur devient une
/// [EventActionException] avec un message en français : jamais de plantage.
class EventCalendarLauncher {
  EventCalendarLauncher._();

  static Future<void> open(CalendarEntry entry) async {
    final event = cal.Event(
      title: entry.title,
      description: entry.description,
      location: entry.location,
      startDate: entry.start,
      endDate: entry.end,
      // iOS : alarme réellement créée [alarmMinutes] AVANT le début (le
      // plugin la place à -durée). Android : ignoré par le plugin, voir la
      // limite expliquée dans EventCalendarSync.reminderMinutes.
      iosParams: cal.IOSParams(reminder: Duration(minutes: entry.alarmMinutes)),
    );

    bool opened;
    try {
      opened = await cal.Add2Calendar.addEvent2Cal(event);
    } on MissingPluginException {
      throw const EventActionException("Le calendrier n'est pas disponible sur cet appareil.");
    } on PlatformException catch (e) {
      throw EventActionException("Impossible d'ouvrir le calendrier : ${e.message ?? e.code}.");
    }
    if (!opened) {
      throw const EventActionException(
          "Aucune application Calendrier n'a été trouvée. Installez Google Agenda puis réessayez.");
    }
  }
}
