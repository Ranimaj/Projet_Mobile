import '../../core/utils/article_search.dart';

enum ModerationLevel { block, warn }

/// Un problème détecté dans une annonce.
class ModerationIssue {
  final ModerationLevel level;
  final String message;
  const ModerationIssue(this.level, this.message);
}

class ModerationResult {
  final List<ModerationIssue> issues;
  const ModerationResult(this.issues);

  bool get blocked => issues.any((i) => i.level == ModerationLevel.block);
  bool get hasWarnings => issues.any((i) => i.level == ModerationLevel.warn);
  bool get ok => issues.isEmpty;

  List<String> messages(ModerationLevel level) =>
      [for (final i in issues) if (i.level == level) i.message];
}

/// Objets interdits sur une marketplace étudiante (forme normalisée, sans
/// accents). Un mot suffit à bloquer.
const Map<String, String> _forbidden = {
  'arme': 'les armes', 'armes': 'les armes', 'pistolet': 'les armes',
  'munition': 'les armes', 'munitions': 'les armes',
  'drogue': 'la drogue', 'cannabis': 'la drogue', 'zatla': 'la drogue', 'cocaine': 'la drogue',
  'medicament': 'les médicaments', 'medicaments': 'les médicaments', 'ordonnance': 'les médicaments',
  'alcool': 'l\'alcool', 'cigarette': 'le tabac', 'cigarettes': 'le tabac', 'tabac': 'le tabac',
};

/// Combinaisons interdites (tous les mots doivent être présents).
const _forbiddenPairs = [
  (['sujet', 'examen'], 'les sujets d\'examen'),
  (['fausse', 'carte'], 'les faux documents'),
  (['faux', 'diplome'], 'les faux documents'),
  (['faux', 'certificat'], 'les faux documents'),
];

/// Insultes courantes (liste courte, normalisée).
const _insults = {'con', 'connard', 'conne', 'salope', 'pute', 'merde', 'idiot', 'imbecile', 'debile'};

final _phone = RegExp(r'(\+?216)?[\s.-]?\b[2-9]\d(?:[\s.-]?\d{3}){2}\b');
final _email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+');
final _link = RegExp(r'(https?://|www\.)\S+', caseSensitive: false);

/// Vérifie une annonce avant publication : objets interdits et insultes
/// (bloquant) ; coordonnées personnelles, titre en majuscules, prix
/// suspect (avertissement). Fonctionne sans réseau.
ModerationResult moderateArticle({
  required String title,
  required String description,
  required String category,
  double? price,
}) {
  final issues = <ModerationIssue>[];
  final words = normalizeSearch('$title $description').split(' ').toSet();

  final banned = <String>{};
  for (final w in words) {
    final what = _forbidden[w];
    if (what != null) banned.add(what);
  }
  for (final (pair, what) in _forbiddenPairs) {
    if (pair.every(words.contains)) banned.add(what);
  }
  for (final what in banned) {
    issues.add(ModerationIssue(ModerationLevel.block, 'La vente de $what est interdite sur CampusConnect.'));
  }
  if (words.any(_insults.contains)) {
    issues.add(const ModerationIssue(ModerationLevel.block, 'L\'annonce contient un langage insultant.'));
  }

  final raw = '$title\n$description';
  if (_phone.hasMatch(raw) || _email.hasMatch(raw) || _link.hasMatch(raw)) {
    issues.add(const ModerationIssue(ModerationLevel.warn,
        'Évite de publier ton numéro, ton e-mail ou un lien : utilise la messagerie de l\'app.'));
  }
  final letters = title.replaceAll(RegExp(r'[^A-Za-zÀ-ÿ]'), '');
  if (letters.length >= 6 && letters == letters.toUpperCase()) {
    issues.add(const ModerationIssue(ModerationLevel.warn, 'Le titre est tout en majuscules.'));
  }
  if (price != null) {
    if (price > 5000) {
      issues.add(const ModerationIssue(ModerationLevel.warn, 'Le prix semble très élevé pour le campus.'));
    } else if (category == 'Électronique' && price < 2) {
      issues.add(const ModerationIssue(ModerationLevel.warn,
          'Prix très bas pour de l\'électronique : vérifie qu\'il n\'y a pas d\'erreur (ou coche « Don »).'));
    }
  }
  return ModerationResult(issues);
}
