import '../../models/user_model.dart';

/// Niveau de confiance affiché sous forme de badge.
enum TrustLevel {
  nouveau('Nouveau', 0),
  bronze('Bronze', 30),
  argent('Argent', 55),
  or('Or', 80);

  const TrustLevel(this.label, this.minScore);
  final String label;

  /// Score minimal pour atteindre ce niveau.
  final int minScore;

  static TrustLevel forScore(int score) =>
      values.lastWhere((l) => score >= l.minScore, orElse: () => nouveau);

  /// Niveau suivant, `null` pour Or.
  TrustLevel? get next => index + 1 < values.length ? values[index + 1] : null;
}

/// Un critère du score : points gagnés sur le maximum possible, et conseil
/// pour progresser.
class TrustFactor {
  final String label;
  final int points;
  final int max;
  final String? tip;

  const TrustFactor(this.label, this.points, this.max, {this.tip});

  bool get complete => points >= max;
}

/// Score de confiance sur 100, calculé à partir d'informations publiques du
/// profil (badges de vérification, ancienneté, avis) et de l'activité sur la
/// marketplace. Les signalements confirmés par un admin le font baisser.
class TrustScore {
  final int score;
  final TrustLevel level;
  final List<TrustFactor> factors;

  /// Points retirés à cause des signalements confirmés.
  final int penalty;

  const TrustScore._(this.score, this.level, this.factors, this.penalty);

  static const cardPoints = 25;
  static const phonePoints = 15;
  static const twoFactorPoints = 10;
  static const agePointsMax = 15;
  static const salesPointsMax = 15;
  static const pointsPerSale = 3;
  static const ratingPointsMax = 20;

  /// Avis nécessaires pour compter à plein (moins d'avis = poids réduit).
  static const ratingsForFullWeight = 5;
  static const pointsPerReport = 15;

  factory TrustScore.of(AppUser user, {int completedSales = 0, DateTime? now}) {
    final today = now ?? DateTime.now();
    final card = user.isVerifiedStudent || user.studentCard.status == StudentCardStatus.verified;
    final months = ((today.difference(user.createdAt).inDays) / 30).floor().clamp(0, agePointsMax);
    final sales = (completedSales * pointsPerSale).clamp(0, salesPointsMax);
    final ratingWeight = (user.ratingCount / ratingsForFullWeight).clamp(0.0, 1.0);
    final rating = user.ratingCount == 0
        ? 0
        : (user.ratingAverage.clamp(0, 5) / 5 * ratingPointsMax * ratingWeight).round();

    final factors = [
      TrustFactor('Carte étudiant vérifiée', card ? cardPoints : 0, cardPoints,
          tip: 'Envoie ta carte étudiant depuis ton profil.'),
      TrustFactor('Téléphone vérifié', user.isPhoneVerified ? phonePoints : 0, phonePoints,
          tip: 'Vérifie ton numéro par SMS.'),
      TrustFactor('Double authentification', user.twoFactorEnabled ? twoFactorPoints : 0, twoFactorPoints,
          tip: 'Active-la dans Profil › Sécurité.'),
      TrustFactor('Ancienneté du compte', months, agePointsMax, tip: '1 point par mois sur CampusConnect.'),
      TrustFactor('Ventes et dons conclus', sales, salesPointsMax,
          tip: '$pointsPerSale points par article marqué vendu ou donné.'),
      TrustFactor('Avis reçus', rating, ratingPointsMax, tip: 'Les avis des acheteurs comptent ici.'),
    ];
    final penalty = user.reportCount * pointsPerReport;
    final raw = factors.fold<int>(0, (sum, f) => sum + f.points) - penalty;
    final score = user.disabled ? 0 : raw.clamp(0, 100);
    return TrustScore._(score, TrustLevel.forScore(score), factors, penalty);
  }

  /// Points manquants pour le niveau suivant (`null` au niveau Or).
  int? get pointsToNextLevel {
    final next = level.next;
    return next == null ? null : next.minScore - score;
  }
}
