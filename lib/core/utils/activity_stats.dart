import '../../models/annonce_model.dart';
import '../../models/article_model.dart';
import '../../models/event_model.dart';
import '../../models/job_offer_model.dart';
import '../../widgets/charts/chart_models.dart';
import 'fr_dates.dart';

/// Activité de [userId] sur les 7 derniers jours (aujourd'hui inclus, le plus
/// ancien d'abord) : objets publiés, annonces publiées, événements organisés
/// et candidatures envoyées, comptés par jour.
List<ChartPoint> weeklyActivity({
  required String userId,
  required List<ArticleModel> articles,
  required List<AnnonceModel> notices,
  required List<EventModel> events,
  required List<ApplicationModel> applications,
  required DateTime now,
}) {
  bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  final today = DateTime(now.year, now.month, now.day);
  return [
    for (var i = 6; i >= 0; i--)
      () {
        // Calendar arithmetic, not Duration: stays correct across DST changes.
        final day = DateTime(today.year, today.month, today.day - i);
        final count = articles
                .where((a) => a.ownerId == userId && sameDay(a.createdAt, day))
                .length +
            notices
                .where((n) => n.authorId == userId && sameDay(n.createdAt, day))
                .length +
            events
                .where(
                    (e) => e.organizerId == userId && sameDay(e.startDate, day))
                .length +
            applications
                .where(
                    (p) => p.candidateId == userId && sameDay(p.appliedAt, day))
                .length;
        return ChartPoint(
            label: FrDates.dayShort[day.weekday - 1], value: count.toDouble());
      }(),
  ];
}
