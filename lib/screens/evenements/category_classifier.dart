import 'dart:math' as math;

import 'event_categories.dart';

/// Suggestion de catégorie : une valeur de [EventCategories.all] (le type
/// utilisé par la liste déroulante) et sa probabilité (0..1).
class CategorySuggestion {
  final String category;
  final double probability;
  const CategorySuggestion(this.category, this.probability);

  @override
  bool operator ==(Object other) =>
      other is CategorySuggestion && other.category == category && other.probability == probability;

  @override
  int get hashCode => Object.hash(category, probability);

  @override
  String toString() => 'CategorySuggestion($category, $probability)';
}

/// Classifieur de catégorie embarqué (pure Dart, aucune dépendance Flutter).
///
/// Reproduit EXACTEMENT `ml/train.py` (TF-IDF + régression logistique) à
/// partir du modèle exporté `assets/ml/category_model.json` :
/// 1. normalisation : minuscules puis accents retirés (comme NFD + suppression
///    des marques combinantes en Python) ;
/// 2. mots = suites `[a-z0-9]+` de 2 caractères ou plus, hors mots vides,
///    plus les paires de mots voisins jointes par `_` ;
/// 3. seuls les termes du vocabulaire comptent : `tf = 1 + ln(n)`,
///    `x = tf × idf`, normalisation L2 ;
/// 4. `score_k = biais_k + Σ x·w_k`, puis softmax.
///
/// Parité vérifiée par test/evenements/category_classifier_test.dart avec
/// les vecteurs de référence produits par Python.
class CategoryClassifier {
  /// Libellés des classes, dans l'ordre des colonnes de poids.
  final List<String> classes;

  /// En dessous de cette probabilité, aucune suggestion.
  final double threshold;
  final Set<String> stopwords;
  final List<double> intercepts;

  /// terme → [idf, w_0, …, w_{k-1}].
  final Map<String, List<double>> terms;

  CategoryClassifier._(this.classes, this.threshold, this.stopwords, this.intercepts, this.terms);

  /// Lit le JSON exporté par train.py. Lève une [FormatException] si la
  /// structure ne correspond pas (le chargeur la transforme en « pas de
  /// suggestion »).
  factory CategoryClassifier.fromJson(Map<String, dynamic> json) {
    try {
      final classes = (json['classes'] as List).cast<String>().toList(growable: false);
      final threshold = (json['threshold'] as num).toDouble();
      final stopwords = (json['stopwords'] as List).cast<String>().toSet();
      final intercepts =
          (json['intercepts'] as List).map((v) => (v as num).toDouble()).toList(growable: false);
      final rawTerms = json['terms'] as Map<String, dynamic>;
      if (classes.isEmpty || intercepts.length != classes.length) {
        throw const FormatException('classes / intercepts incohérents');
      }
      final terms = <String, List<double>>{};
      rawTerms.forEach((term, row) {
        final values = (row as List).map((v) => (v as num).toDouble()).toList(growable: false);
        if (values.length != classes.length + 1) {
          throw FormatException('terme "$term" : ${values.length} valeurs au lieu de ${classes.length + 1}');
        }
        terms[term] = values;
      });
      return CategoryClassifier._(classes, threshold, stopwords, intercepts, terms);
    } on FormatException {
      rethrow;
    } catch (e) {
      // Cast raté (TypeError), clé absente… : même traitement.
      throw FormatException('modèle de catégorie invalide : $e');
    }
  }

  static const Map<String, String> _accents = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', //
    'ç': 'c',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
    'ñ': 'n',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
    'ý': 'y', 'ÿ': 'y',
  };

  /// Minuscules, puis accents retirés. Les marques combinantes déjà séparées
  /// (U+0300–U+036F, ex. « e » + accent aigu collé depuis un autre logiciel)
  /// sont aussi retirées, comme le fait NFD + filtrage « Mn » en Python. Tout
  /// autre caractère (œ, apostrophe, tiret…) reste tel quel et servira de
  /// séparateur dans [features].
  static String normalize(String text) {
    final out = StringBuffer();
    for (final rune in text.toLowerCase().runes) {
      if (rune >= 0x0300 && rune <= 0x036F) continue;
      final ch = String.fromCharCode(rune);
      out.write(_accents[ch] ?? ch);
    }
    return out.toString();
  }

  static final RegExp _word = RegExp('[a-z0-9]+');

  /// Mots (≥ 2 caractères, hors mots vides) puis bigrammes `a_b` des mots
  /// voisins APRÈS filtrage — identique à `tokenize` de train.py.
  List<String> features(String text) {
    final tokens = _word
        .allMatches(normalize(text))
        .map((m) => m.group(0)!)
        .where((t) => t.length >= 2 && !stopwords.contains(t))
        .toList();
    return [
      ...tokens,
      for (var i = 0; i + 1 < tokens.length; i++) '${tokens[i]}_${tokens[i + 1]}',
    ];
  }

  /// Nombre de termes distincts du texte présents dans le vocabulaire.
  int knownTermCount(String text) => features(text).where(terms.containsKey).toSet().length;

  /// Probabilité de chaque classe (même ordre que [classes]). Un texte sans
  /// terme connu donne le softmax des seuls biais, comme en Python.
  List<double> probabilities(String text) {
    final counts = <String, int>{};
    for (final f in features(text)) {
      if (terms.containsKey(f)) counts[f] = (counts[f] ?? 0) + 1;
    }
    final x = <String, double>{
      for (final e in counts.entries) e.key: (1 + math.log(e.value)) * terms[e.key]![0],
    };
    final norm = math.sqrt(x.values.fold<double>(0, (s, v) => s + v * v));
    final scores = List<double>.of(intercepts);
    if (norm > 0) {
      x.forEach((term, v) {
        final row = terms[term]!;
        for (var k = 0; k < scores.length; k++) {
          scores[k] += (v / norm) * row[1 + k];
        }
      });
    }
    final maxScore = scores.reduce(math.max);
    final exps = scores.map((s) => math.exp(s - maxScore)).toList();
    final z = exps.fold<double>(0, (s, v) => s + v);
    return exps.map((v) => v / z).toList();
  }

  /// Texte analysé : « titre. description », comme les exemples d'entraînement.
  static String combine(String title, String description) =>
      [title.trim(), description.trim()].where((s) => s.isNotEmpty).join('. ');

  /// Catégorie suggérée, ou null si : aucun terme connu, probabilité maximale
  /// sous le seuil, ou libellé du modèle absent de [EventCategories.all].
  CategorySuggestion? suggest(String title, String description) {
    final text = combine(title, description);
    if (knownTermCount(text) == 0) return null;
    final probs = probabilities(text);
    var best = 0;
    for (var k = 1; k < probs.length; k++) {
      if (probs[k] > probs[best]) best = k;
    }
    if (probs[best] < threshold) return null;
    final category = categoryFor(classes[best]);
    return category == null ? null : CategorySuggestion(category, probs[best]);
  }

  /// Libellé du modèle → valeur de la liste déroulante (null si inconnu).
  static String? categoryFor(String label) => EventCategories.all.contains(label) ? label : null;
}
