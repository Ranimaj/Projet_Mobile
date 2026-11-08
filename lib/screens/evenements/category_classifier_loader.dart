import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'category_classifier.dart';

/// Charge `assets/ml/category_model.json` une seule fois (résultat mis en
/// cache, y compris un échec). Toute erreur = « pas de suggestion » (null),
/// jamais de crash. Aucun accès réseau.
class CategoryClassifierLoader {
  CategoryClassifierLoader._();

  static const String assetPath = 'assets/ml/category_model.json';

  static Future<CategoryClassifier?>? _cached;

  static Future<CategoryClassifier?> load({AssetBundle? bundle}) =>
      _cached ??= _load(bundle ?? rootBundle);

  static Future<CategoryClassifier?> _load(AssetBundle bundle) async {
    try {
      final raw = await bundle.loadString(assetPath);
      return CategoryClassifier.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Modèle de catégorie indisponible : $e');
      return null;
    }
  }

  @visibleForTesting
  static void resetCache() => _cached = null;
}
