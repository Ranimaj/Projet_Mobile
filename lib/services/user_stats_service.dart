import '../models/user_model.dart';
import '../widgets/charts/chart_models.dart';

/// Indicateurs d'inscription calculés côté client à partir de la liste des
/// comptes.
class UserStats {
  final int signUps;

  /// Évolution en % par rapport à la période précédente de même durée ;
  /// `null` quand celle-ci est vide.
  final double? changePercent;
  final int pendingCards;
  final List<ChartPoint> signUpsPerDay;
  final Map<UserRole, int> byRole;
  final Map<StudentCardStatus, int> cardsByStatus;

  const UserStats({
    required this.signUps,
    required this.changePercent,
    required this.pendingCards,
    required this.signUpsPerDay,
    required this.byRole,
    required this.cardsByStatus,
  });
}

/// Fenêtre = les [days] derniers jours, aujourd'hui inclus. Les répartitions
/// par rôle et par statut de carte portent sur tous les comptes.
UserStats aggregate(List<AppUser> users,
    {required DateTime now, required int days}) {
  final today = DateTime(now.year, now.month, now.day);
  final start = DateTime(today.year, today.month, today.day - (days - 1));
  final previousStart =
      DateTime(today.year, today.month, today.day - (2 * days - 1));

  final perDay = <DateTime, int>{};
  var current = 0;
  var previous = 0;
  for (final user in users) {
    final c = user.createdAt;
    final day = DateTime(c.year, c.month, c.day);
    if (!day.isBefore(start) && !day.isAfter(today)) {
      current++;
      perDay[day] = (perDay[day] ?? 0) + 1;
    } else if (!day.isBefore(previousStart) && day.isBefore(start)) {
      previous++;
    }
  }

  final points = <ChartPoint>[
    for (var i = 0; i < days; i++)
      () {
        final day = DateTime(start.year, start.month, start.day + i);
        return ChartPoint(
          label: days <= 7 ? '${day.day}' : '${day.day}/${day.month}',
          value: (perDay[day] ?? 0).toDouble(),
        );
      }(),
  ];

  final byRole = <UserRole, int>{};
  final cards = <StudentCardStatus, int>{};
  for (final user in users) {
    byRole[user.role] = (byRole[user.role] ?? 0) + 1;
    final status = user.studentCard.status;
    cards[status] = (cards[status] ?? 0) + 1;
  }

  return UserStats(
    signUps: current,
    changePercent: previous == 0 ? null : (current - previous) / previous * 100,
    pendingCards: cards[StudentCardStatus.pending] ?? 0,
    signUpsPerDay: points,
    byRole: byRole,
    cardsByStatus: cards,
  );
}
