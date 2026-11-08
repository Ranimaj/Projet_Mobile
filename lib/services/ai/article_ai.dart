import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart'
    show Content, FirebaseAI, GenerativeModel, InlineDataPart, Part, TextPart;
import 'package:firebase_app_check/firebase_app_check.dart' show FirebaseAppCheck;
import 'package:flutter_image_compress/flutter_image_compress.dart' show CompressFormat, FlutterImageCompress;
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart'
    show ImageLabeler, ImageLabelerOptions, InputImage;

import 'category_mapper.dart';

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

/// Rédige une description d'annonce (nécessite le réseau).
abstract class DescriptionWriter {
  Future<String> write(DescriptionRequest request);
}

/// Gemini via Firebase AI Logic (API Gemini Developer).
class GeminiDescriptionWriter implements DescriptionWriter {
  GeminiDescriptionWriter({this.model = 'gemini-3.8-flash'});

  final String model;
  GenerativeModel? _model;

  @override
  Future<String> write(DescriptionRequest request) async {
    // Le jeton App Check n'est envoyé que si on passe l'instance explicitement.
    final m = _model ??= FirebaseAI.googleAI(appCheck: FirebaseAppCheck.instance)
        .generativeModel(model: model);
    final photo = await _smallJpeg(request.photo);
    String text;
    try {
      text = await _generate(m, request.prompt, photo);
    } catch (_) {
      // Serveur saturé ou délai dépassé (503) : un 2e essai, sans la photo
      // (plus léger, donc plus rapide).
      await Future<void>.delayed(const Duration(seconds: 2));
      text = await _generate(m, request.prompt, null);
    }
    return text.length > 1000 ? text.substring(0, 1000) : text;
  }

  Future<String> _generate(GenerativeModel m, String prompt, List<int>? photo) async {
    final parts = <Part>[
      TextPart(prompt),
      if (photo != null) InlineDataPart('image/jpeg', Uint8List.fromList(photo)),
    ];
    final response = await m
        .generateContent([Content.multi(parts)])
        .timeout(const Duration(seconds: 40));
    final text = response.text?.trim() ?? '';
    if (text.isEmpty) throw StateError('Réponse vide');
    return text;
  }

  /// Réduit la photo (≤ 768 px, JPEG) pour un envoi rapide. Null si absente.
  static Future<List<int>?> _smallJpeg(File? photo) async {
    if (photo == null) return null;
    try {
      final out = await FlutterImageCompress.compressWithFile(photo.path,
          minWidth: 768, minHeight: 768, quality: 75, format: CompressFormat.jpeg);
      if (out != null) return out;
    } catch (_) {}
    return photo.readAsBytes();
  }
}

/// Point d'accès unique aux fonctions IA de Vente & Don (remplaçable dans
/// les tests).
class ArticleAi {
  ArticleAi({ImageTagger? tagger, DescriptionWriter? writer})
      : tagger = tagger ?? MlKitImageTagger(),
        writer = writer ?? GeminiDescriptionWriter();

  final ImageTagger tagger;
  final DescriptionWriter writer;

  static ArticleAi? _instance;
  static ArticleAi get instance => _instance ??= ArticleAi();
}
