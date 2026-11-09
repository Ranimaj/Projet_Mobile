import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show SynchronousFuture, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;

import '../../core/utils/article_search.dart';
import '../../core/utils/trust_score.dart';
import '../../models/article_model.dart';

/// Niveau de risque d'arnaque d'une annonce.
enum FraudRisk { low, medium, high }

/// Résultat de l'analyse anti-arnaque d'une annonce.
class FraudReport {
  /// Probabilité d'arnaque calculée par le modèle (0 à 1).
  final double probability;
  final FraudRisk risk;

  /// Indices trouvés, du plus important au moins important (3 au plus).
  final List<String> reasons;

  const FraudReport({required this.probability, required this.risk, required this.reasons});

  int get percent => (probability * 100).round();
}

/// Mots et expressions cherchés dans l'annonce (forme normalisée, sans
/// accents). Identiques à `tools/fraud_model/train_fraud_model.py`.
const Map<String, List<String>> _groups = {
  'payment': [
    'avance', 'acompte', 'virement', 'd17', 'flouci', 'mandat', 'western union',
    'paiement avant', 'payer avant', 'payez avant', 'paiement d abord', 'recharge',
    'carte cadeau', 'transfert', 'rib', 'e dinar', 'edinar', 'frais de livraison',
    'frais d envoi',
  ],
  'off_app': ['whatsapp', 'telegram', 'messenger', 'instagram', 'insta', 'snapchat', 'viber'],
  'urgency': [
    'urgent', 'urgence', 'vite', 'rapidement', 'aujourd hui seulement',
    'premier arrive', 'derniere chance', 'depechez', 'dernier jour', 'offre limitee',
  ],
  'no_meeting': [
    'livraison seulement', 'uniquement livraison', 'pas de rencontre',
    'pas de remise en main propre', 'envoi par poste', 'par la poste',
    'a l etranger', 'hors campus', 'pas sur le campus', 'envoi uniquement',
  ],
  'high_value': [
    'iphone', 'macbook', 'ipad', 'airpods', 'ps5', 'playstation', 'galaxy',
    'rolex', 'laptop', 'pc portable', 'ordinateur portable', 'xbox',
    'nintendo switch', 'apple watch', 'gopro', 'drone',
  ],
  'too_good': [
    'sous blister', 'jamais utilise', 'jamais servi', '100 neuf', 'original garanti',
    'prix sacrifie', 'prix casse', 'cadeau',
  ],
};

/// Prix bas habituel par catégorie (occasion étudiante).
const Map<String, double> _referenceLow = {
  'Livres': 10, 'Électronique': 30, 'Vêtements': 10, 'Mobilier': 20, 'Autre': 5,
};

final _phone = RegExp(r'(\+?216)?[\s.-]?\b[2-9]\d(?:[\s.-]?\d{3}){2}\b');
final _email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+');
final _link = RegExp(r'(https?://|www\.)\S+', caseSensitive: false);

/// Explication affichée pour chaque indice.
const Map<String, String> _reasonText = {
  'payment': 'Demande un paiement à l\'avance (virement, D17, Flouci, recharge…).',
  'off_app': 'Pousse à discuter hors de l\'app (numéro, WhatsApp, lien…).',
  'urgency': 'Met la pression pour décider vite.',
  'no_meeting': 'Refuse la remise en main propre sur le campus.',
  'high_value_cheap': 'Objet de valeur à un prix beaucoup trop bas.',
  'price_far_below': 'Prix très en dessous de l\'habituel pour la catégorie.',
  'too_good': 'Promesse « trop belle » (sous blister, jamais utilisé…).',
  'free_but_pay': 'Annoncé gratuit mais demande de payer quelque chose.',
  'short_description': 'Description très courte.',
  'no_photo': 'Pas de photo de l\'objet.',
  'shouting': 'Majuscules ou points d\'exclamation en excès.',
  'untrusted_seller': 'Vendeur récent et peu vérifié (score de confiance bas).',
};

/// Poids du score de confiance du vendeur, ajouté au calcul du modèle (en
/// échelle logit) : de +[kSellerTrustWeight] pour un score de 0 à
/// −[kSellerTrustWeight] pour 100. Le modèle entraîné ne connaît que le texte
/// de l'annonce ; ce terme s'y ajoute sans réentraînement.
const double kSellerTrustWeight = 1.2;

/// Logit ajouté pour un vendeur au score [trust] (0 à 100).
double sellerTrustShift(int trust) => (0.5 - trust.clamp(0, 100) / 100) * 2 * kSellerTrustWeight;

bool _hasAny(String normalized, List<String> phrases) {
  final padded = ' $normalized ';
  return phrases.any((p) => padded.contains(' $p '));
}

/// Les 11 caractéristiques lues par le modèle (0 ou 1, sauf
/// `price_far_below` entre 0 et 1). Même calcul que le script Python.
Map<String, double> fraudFeatures({
  required String title,
  required String description,
  required String category,
  double? price,
  required bool hasPhoto,
}) {
  final norm = normalizeSearch('$title $description');
  final raw = '$title\n$description';
  final letters = title.replaceAll(RegExp(r'[^A-Za-zÀ-ÿ]'), '');
  final words = normalizeSearch(description).split(' ').where((w) => w.isNotEmpty).length;
  double b(bool v) => v ? 1 : 0;
  final payment = _hasAny(norm, _groups['payment']!);
  return {
    'payment': b(payment),
    'off_app': b(_hasAny(norm, _groups['off_app']!) ||
        _phone.hasMatch(raw) ||
        _email.hasMatch(raw) ||
        _link.hasMatch(raw)),
    'urgency': b(_hasAny(norm, _groups['urgency']!)),
    'no_meeting': b(_hasAny(norm, _groups['no_meeting']!)),
    'high_value_cheap': b(price != null && price < 150 && _hasAny(norm, _groups['high_value']!)),
    'price_far_below':
        price == null ? 0 : (1 - price / (_referenceLow[category] ?? 5)).clamp(0.0, 1.0).toDouble(),
    'too_good': b(_hasAny(norm, _groups['too_good']!)),
    'free_but_pay': b(price == null && payment),
    'short_description': b(words < 8),
    'no_photo': b(!hasPhoto),
    'shouting': b('!'.allMatches(raw).length >= 3 || (letters.length >= 6 && letters == letters.toUpperCase())),
  };
}

/// Modèle anti-arnaque **embarqué** : régression logistique entraînée en
/// Python (scikit-learn) sur 1 350 annonces, voir
/// `tools/fraud_model/train_fraud_model.py`. Les poids sont dans
/// `assets/models/fraud_model.json` ; le calcul se fait dans le téléphone,
/// sans internet.
class FraudModel {
  final double bias;
  final Map<String, double> weights;
  final double mediumThreshold;
  final double highThreshold;
  final Map<String, dynamic> metrics;

  const FraudModel({
    required this.bias,
    required this.weights,
    this.mediumThreshold = 0.3,
    this.highThreshold = 0.6,
    this.metrics = const {},
  });

  factory FraudModel.fromJson(Map<String, dynamic> json) {
    final thresholds = (json['thresholds'] as Map?) ?? const {};
    return FraudModel(
      bias: (json['bias'] as num).toDouble(),
      weights: {
        for (final e in (json['features'] as Map).entries) e.key as String: (e.value as num).toDouble(),
      },
      mediumThreshold: (thresholds['medium'] as num?)?.toDouble() ?? 0.3,
      highThreshold: (thresholds['high'] as num?)?.toDouble() ?? 0.6,
      metrics: Map<String, dynamic>.from((json['metrics'] as Map?) ?? const {}),
    );
  }

  static const assetPath = 'assets/models/fraud_model.json';
  static FraudModel? _cached;

  /// Modèle déjà chargé (les tests peuvent en fournir un).
  @visibleForTesting
  static set cached(FraudModel? model) => _cached = model;

  /// Charge le modèle une seule fois depuis les assets de l'app.
  static Future<FraudModel> load() {
    final model = _cached;
    if (model != null) return SynchronousFuture(model);
    return rootBundle.loadString(assetPath).then((text) {
      return _cached = FraudModel.fromJson(jsonDecode(text) as Map<String, dynamic>);
    });
  }

  /// Probabilité d'arnaque pour ces caractéristiques.
  double probability(Map<String, double> features) {
    var z = bias;
    features.forEach((name, value) => z += (weights[name] ?? 0) * value);
    return 1 / (1 + math.exp(-z));
  }

  FraudReport analyze({
    required String title,
    required String description,
    required String category,
    double? price,
    required bool hasPhoto,
    TrustScore? sellerTrust,
  }) {
    final f = fraudFeatures(
      title: title,
      description: description,
      category: category,
      price: price,
      hasPhoto: hasPhoto,
    );
    var p = probability(f);
    final shift = sellerTrust == null ? 0.0 : sellerTrustShift(sellerTrust.score);
    if (shift != 0) {
      final logit = math.log(p / (1 - p));
      p = 1 / (1 + math.exp(-(logit + shift)));
    }
    final contributions = [
      for (final e in f.entries)
        if (e.value > 0 && (weights[e.key] ?? 0) > 0) (e.key, e.value * weights[e.key]!),
      if (shift > 0 && sellerTrust!.level == TrustLevel.nouveau) ('untrusted_seller', shift),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return FraudReport(
      probability: p,
      risk: p >= highThreshold
          ? FraudRisk.high
          : p >= mediumThreshold
              ? FraudRisk.medium
              : FraudRisk.low,
      reasons: [for (final (name, _) in contributions.take(3)) _reasonText[name] ?? name],
    );
  }

  /// [sellerTrust] : score de confiance du vendeur, s'il est connu.
  FraudReport analyzeArticle(ArticleModel article, {TrustScore? sellerTrust}) => analyze(
        title: article.title,
        description: article.description,
        category: article.category,
        price: article.price,
        hasPhoto: article.imageUrls.isNotEmpty,
        sellerTrust: sellerTrust,
      );
}
