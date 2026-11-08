import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show SynchronousFuture, visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;

import '../../core/utils/article_search.dart';
import '../../models/article_model.dart';

/// Expéditeur des messages écrits par l'assistant IA dans une conversation.
const String kAssistantId = 'campusconnect-assistant';

/// Mots et paires de mots voisins d'un message — identique à `terms()` dans
/// `tools/chat_model/train_chat_model.py`.
Set<String> chatTerms(String text) {
  final words = normalizeSearch(text).split(' ').where((w) => w.isNotEmpty).toList();
  return {
    ...words,
    for (var i = 0; i + 1 < words.length; i++) '${words[i]} ${words[i + 1]}',
  };
}

/// Intention reconnue dans un message, avec la confiance du modèle (0 à 1).
class ChatIntent {
  final String name;
  final double confidence;
  const ChatIntent(this.name, this.confidence);

  @override
  String toString() => '$name (${(confidence * 100).round()} %)';
}

/// Modèle **embarqué** qui reconnaît l'intention d'un message d'acheteur
/// (disponibilité, prix, négociation, état, rendez-vous, livraison…), en
/// français et en darija écrite en lettres latines. Régression logistique
/// multiclasse entraînée en Python (`tools/chat_model/train_chat_model.py`),
/// poids dans `assets/models/chat_model.json`, calcul dans le téléphone.
class ChatIntentModel {
  final List<String> classes;
  final List<double> bias;
  final Map<String, List<double>> terms;
  final double minConfidence;
  final Map<String, dynamic> metrics;

  const ChatIntentModel({
    required this.classes,
    required this.bias,
    required this.terms,
    this.minConfidence = 0.45,
    this.metrics = const {},
  });

  factory ChatIntentModel.fromJson(Map<String, dynamic> json) => ChatIntentModel(
        classes: List<String>.from(json['classes'] as List),
        bias: [for (final b in json['bias'] as List) (b as num).toDouble()],
        terms: {
          for (final e in (json['terms'] as Map).entries)
            e.key as String: [for (final w in e.value as List) (w as num).toDouble()],
        },
        minConfidence: (json['minConfidence'] as num?)?.toDouble() ?? 0.45,
        metrics: Map<String, dynamic>.from((json['metrics'] as Map?) ?? const {}),
      );

  static const assetPath = 'assets/models/chat_model.json';
  static ChatIntentModel? _cached;

  @visibleForTesting
  static set cached(ChatIntentModel? model) => _cached = model;

  /// Charge le modèle une seule fois depuis les assets de l'app.
  static Future<ChatIntentModel> load() {
    final model = _cached;
    if (model != null) return SynchronousFuture(model);
    return rootBundle.loadString(assetPath).then(
        (text) => _cached = ChatIntentModel.fromJson(jsonDecode(text) as Map<String, dynamic>));
  }

  /// Toutes les intentions, de la plus probable à la moins probable.
  List<ChatIntent> rank(String message) {
    final z = List<double>.of(bias);
    for (final term in chatTerms(message)) {
      final w = terms[term];
      if (w == null) continue;
      for (var k = 0; k < z.length; k++) {
        z[k] += w[k];
      }
    }
    final top = z.reduce(math.max);
    final e = [for (final v in z) math.exp(v - top)];
    final sum = e.reduce((a, b) => a + b);
    return [for (var k = 0; k < classes.length; k++) ChatIntent(classes[k], e[k] / sum)]
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
  }

  ChatIntent classify(String message) => rank(message).first;
}

/// Assistant IA du vendeur : répond tout de suite à l'acheteur avec les
/// informations de l'annonce. Le vendeur peut toujours répondre lui-même.
class ChatAssistant {
  final ChatIntentModel model;
  const ChatAssistant(this.model);

  /// Intentions auxquelles l'assistant sait répondre avec l'annonce.
  static const _answerable = {
    'disponible', 'prix', 'negociation', 'etat', 'details', 'lieu', 'livraison', 'photo', 'reserver',
  };

  /// Réponse à [message] à propos de [article] ; [sellerName] est le prénom
  /// du vendeur. Répond à 2 questions au plus (« c'est dispo et combien ? »).
  String reply(String message, ArticleModel article, {required String sellerName}) {
    final ranked = model.rank(message);
    final first = ranked.first;
    if (first.confidence < model.minConfidence || first.name == 'autre') {
      return 'Je n\'ai pas la réponse à cette question : $sellerName te répondra directement ici.';
    }
    final answers = [_answer(first.name, article, sellerName)];
    if (_answerable.contains(first.name)) {
      final second = ranked[1];
      if (second.confidence >= 0.25 && _answerable.contains(second.name)) {
        answers.add(_answer(second.name, article, sellerName));
      }
    }
    return answers.join('\n');
  }

  String _answer(String intent, ArticleModel a, String seller) {
    final title = '« ${a.title} »';
    switch (intent) {
      case 'salutation':
        return 'Bonjour ! Je suis l\'assistant IA de $seller. Pose-moi ta question sur $title '
            '(disponibilité, prix, état, rendez-vous…).';
      case 'disponible':
        return switch (a.status) {
          ArticleStatus.available => 'Oui, $title est toujours disponible.',
          ArticleStatus.reserved => '$title est réservé pour le moment. $seller te dira s\'il se libère.',
          ArticleStatus.done =>
            'Désolé, $title a déjà été ${a.isFree ? 'donné' : 'vendu'}.',
        };
      case 'prix':
        return a.isFree ? '$title est un don : c\'est gratuit.' : 'Le prix de $title est de ${a.priceLabel}.';
      case 'negociation':
        return a.isFree
            ? '$title est déjà gratuit.'
            : 'Le prix affiché est ${a.priceLabel}. C\'est $seller qui décide s\'il peut le baisser : '
                'il te répondra ici.';
      case 'etat':
        final sentence = _firstSentence(a.description);
        return sentence == null
            ? '$seller n\'a pas décrit l\'état : il te répondra ici.'
            : 'D\'après l\'annonce : « $sentence »';
      case 'details':
        final text = a.description.trim();
        if (text.isEmpty) return '$seller n\'a pas mis de description : il te répondra ici.';
        final short = text.length > 220 ? '${text.substring(0, 220).trimRight()}…' : text;
        return 'Voici la description (${a.category}) : « $short »';
      case 'lieu':
        return 'La remise se fait en main propre sur le campus (bibliothèque, cafétéria, entrée de '
            'l\'école…). Propose un lieu et une heure : $seller confirmera.';
      case 'livraison':
        return 'Pas de livraison : sur CampusConnect, on se voit sur le campus. Ne paie jamais à '
            'l\'avance (D17, virement…) avant d\'avoir vu l\'objet.';
      case 'photo':
        final n = a.imageUrls.length;
        return n == 0
            ? 'L\'annonce n\'a pas encore de photo : demande à $seller, il te répondra ici.'
            : 'Toutes les photos sont dans l\'annonce ($n photo${n > 1 ? 's' : ''}). Pour une autre '
                'photo, $seller te répondra ici.';
      case 'reserver':
        return a.status == ArticleStatus.available
            ? 'Super ! Je préviens $seller : c\'est lui qui peut réserver $title pour toi.'
            : 'Désolé, $title n\'est plus disponible pour le moment.';
      case 'merci':
        return 'Avec plaisir !';
      default:
        return 'Je n\'ai pas la réponse à cette question : $seller te répondra directement ici.';
    }
  }

  static String? _firstSentence(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final end = t.indexOf(RegExp(r'[.!?]'));
    return end <= 0 ? t : t.substring(0, end + 1);
  }
}
