import 'dart:io';

import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart'
    show ImageLabeler, ImageLabelerOptions, InputImage;

import 'category_mapper.dart';
import 'gemini_api_writer.dart';

/// Reconnaît le contenu d'une photo (sur le téléphone, sans réseau).
abstract class ImageTagger {
  Future<List<ImageTag>> tag(File image);
}

/// Google ML Kit Image Labeling : modèle embarqué de ~400 étiquettes.
class MlKitImageTagger implements ImageTagger {
  ImageLabeler? _labeler;

  @override
  Future<List<ImageTag>> tag(File image) async {
    final labeler = _labeler ??= ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.4));
    final labels = await labeler.processImage(InputImage.fromFilePath(image.path));
    return [for (final l in labels) ImageTag(l.label, l.confidence)];
  }
}

/// Informations envoyées à l'IA pour rédiger une description.
class DescriptionRequest {
  final String title;
  final String category;
  final double? price;
  final List<String> keywords;
  final File? photo;

  const DescriptionRequest({
    required this.title,
    required this.category,
    this.price,
    this.keywords = const [],
    this.photo,
  });

  String get prompt => '''
Tu aides un étudiant tunisien à vendre ou donner un objet sur l'application CampusConnect.
Rédige une description d'annonce en français : 2 à 3 phrases courtes, ton simple et honnête,
sans emoji, sans inventer de défaut ni de caractéristique absente de la photo.
Ne mets ni prix, ni numéro de téléphone, ni lien. Termine par la remise en main propre sur le campus.
Titre : $title
Catégorie : $category
${price == null ? 'C\'est un don gratuit.' : 'Prix : ${price!.toStringAsFixed(0)} DT'}
${keywords.isEmpty ? '' : 'Mots-clés détectés sur la photo : ${keywords.join(', ')}'}
Réponds uniquement avec la description.''';
}

/// Rédige une description d'annonce.
abstract class DescriptionWriter {
  Future<String> write(DescriptionRequest request);
}

/// Rédaction **sur le téléphone**, sans réseau ni service externe : compose
/// une description à partir du titre, de la catégorie, du prix et des
/// mots-clés reconnus sur la photo. Le texte varie selon la catégorie et
/// reste court, sans prix ni contact (règles de la modération).
class LocalDescriptionWriter implements DescriptionWriter {
  const LocalDescriptionWriter();

  static const Map<String, String> _detail = {
    'Livres': 'Les pages sont complètes et lisibles, idéal pour réviser.',
    'Électronique': 'Il fonctionne correctement et a été testé avant l\'annonce.',
    'Vêtements': 'Il est propre et a été bien entretenu.',
    'Mobilier': 'Il est solide et pratique pour une chambre ou un studio étudiant.',
  };

  @override
  Future<String> write(DescriptionRequest request) async {
    final title = request.title.trim().isEmpty ? 'Objet' : request.title.trim();
    final what = title[0].toLowerCase() + title.substring(1);
    final words = [
      for (final k in request.keywords)
        if (!what.toLowerCase().contains(k.toLowerCase())) k,
    ].take(3).toList();
    final sentences = <String>[
      request.price == null
          ? 'Je donne $what, en bon état.'
          : 'Je vends $what, en bon état.',
      if (words.isNotEmpty) 'Sur la photo : ${words.join(', ')}.',
      _detail[request.category] ?? 'Il est en bon état et prêt à servir.',
      request.price == null
          ? 'Gratuit pour un étudiant qui en a besoin, remise en main propre sur le campus.'
          : 'Remise en main propre sur le campus.',
    ];
    return sentences.join(' ');
  }
}

/// Point d'accès unique aux fonctions IA de Vente & Don (remplaçable dans
/// les tests).
class ArticleAi {
  ArticleAi({ImageTagger? tagger, DescriptionWriter? writer})
      : tagger = tagger ?? MlKitImageTagger(),
        // Gemini par internet si une clé est fournie, sinon rédaction locale.
        writer = writer ?? GeminiApiDescriptionWriter(apiKey: kGeminiApiKey);

  final ImageTagger tagger;
  final DescriptionWriter writer;

  static ArticleAi? _instance;
  static ArticleAi get instance => _instance ??= ArticleAi();
}
