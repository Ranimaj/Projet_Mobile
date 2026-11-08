/// Étiquette reconnue sur une photo (ML Kit) avec sa confiance (0 à 1).
class ImageTag {
  final String label;
  final double confidence;
  const ImageTag(this.label, this.confidence);

  @override
  String toString() => '$label (${(confidence * 100).round()} %)';
}

/// Catégorie proposée à partir des étiquettes d'une photo.
class CategorySuggestion {
  final String category;
  final double confidence;

  /// Mots-clés en français tirés de la photo (pour le titre / la recherche).
  final List<String> keywords;

  const CategorySuggestion({required this.category, required this.confidence, required this.keywords});
}

/// Étiquettes ML Kit (anglais, en minuscules) → catégorie de l'app.
const Map<String, String> _labelToCategory = {
  // Livres
  'book': 'Livres', 'paper': 'Livres', 'comics': 'Livres', 'poster': 'Livres',
  'newspaper': 'Livres', 'notebook': 'Livres', 'text': 'Livres',
  // Électronique
  'computer': 'Électronique', 'laptop': 'Électronique', 'mobile phone': 'Électronique',
  'cell phone': 'Électronique', 'cellphone': 'Électronique', 'television': 'Électronique',
  'monitor': 'Électronique', 'screen': 'Électronique', 'camera': 'Électronique',
  'headphones': 'Électronique', 'keyboard': 'Électronique', 'calculator': 'Électronique',
  'gadget': 'Électronique', 'musical instrument': 'Électronique', 'joystick': 'Électronique',
  // Vêtements
  'jacket': 'Vêtements', 'jeans': 'Vêtements', 'shoe': 'Vêtements', 'sneakers': 'Vêtements',
  'dress': 'Vêtements', 'hat': 'Vêtements', 'cap': 'Vêtements', 'shirt': 'Vêtements',
  'scarf': 'Vêtements', 'sunglasses': 'Vêtements', 'bag': 'Vêtements', 'handbag': 'Vêtements',
  'clothing': 'Vêtements', 'coat': 'Vêtements', 'sweater': 'Vêtements', 'outerwear': 'Vêtements',
  'uniform': 'Vêtements', 'sleeve': 'Vêtements', 'wristwatch': 'Vêtements',
  // Mobilier
  'desk': 'Mobilier', 'chair': 'Mobilier', 'couch': 'Mobilier', 'bed': 'Mobilier',
  'table': 'Mobilier', 'shelf': 'Mobilier', 'cabinetry': 'Mobilier', 'lamp': 'Mobilier',
  'curtain': 'Mobilier', 'furniture': 'Mobilier', 'cushion': 'Mobilier', 'stool': 'Mobilier',
  'lampshade': 'Mobilier', 'mirror': 'Mobilier',
};

/// Traduction des étiquettes courantes pour les mots-clés affichés.
const Map<String, String> _labelToFrench = {
  'book': 'livre', 'paper': 'papier', 'comics': 'BD', 'poster': 'affiche', 'notebook': 'cahier',
  'computer': 'ordinateur', 'laptop': 'ordinateur portable', 'mobile phone': 'téléphone',
  'cell phone': 'téléphone', 'cellphone': 'téléphone', 'television': 'télévision',
  'monitor': 'écran', 'screen': 'écran', 'camera': 'appareil photo', 'headphones': 'casque',
  'keyboard': 'clavier', 'calculator': 'calculatrice', 'gadget': 'gadget',
  'musical instrument': 'instrument de musique', 'joystick': 'manette',
  'jacket': 'veste', 'jeans': 'jean', 'shoe': 'chaussures', 'sneakers': 'baskets', 'dress': 'robe',
  'hat': 'chapeau', 'cap': 'casquette', 'shirt': 'chemise', 'scarf': 'écharpe',
  'sunglasses': 'lunettes de soleil', 'bag': 'sac', 'handbag': 'sac à main', 'coat': 'manteau',
  'sweater': 'pull', 'outerwear': 'manteau', 'wristwatch': 'montre',
  'desk': 'bureau', 'chair': 'chaise', 'couch': 'canapé', 'bed': 'lit', 'table': 'table',
  'shelf': 'étagère', 'cabinetry': 'meuble', 'lamp': 'lampe', 'curtain': 'rideau',
  'furniture': 'meuble', 'cushion': 'coussin', 'stool': 'tabouret', 'lampshade': 'lampe',
  'mirror': 'miroir', 'bicycle': 'vélo', 'toy': 'jouet', 'guitar': 'guitare', 'plant': 'plante',
};

/// Étiquettes trop vagues pour servir de mot-clé.
const Set<String> _generic = {
  'room', 'wood', 'pattern', 'font', 'rectangle', 'material', 'event', 'fun', 'circle',
  'metal', 'plastic', 'flooring', 'wall', 'interior design', 'product', 'design', 'art',
};

/// Seuil sous lequel une catégorie n'est pas proposée.
const double kMinCategoryConfidence = 0.55;

/// Propose une catégorie (somme des confiances par catégorie) et jusqu'à 4
/// mots-clés français. Renvoie null si rien n'est assez sûr.
CategorySuggestion? suggestCategory(List<ImageTag> tags) {
  final scores = <String, double>{};
  final best = <String, double>{};
  for (final t in tags) {
    final c = _labelToCategory[t.label.toLowerCase()];
    if (c == null) continue;
    scores[c] = (scores[c] ?? 0) + t.confidence;
    if (t.confidence > (best[c] ?? 0)) best[c] = t.confidence;
  }
  final keywords = <String>[];
  for (final t in [...tags]..sort((a, b) => b.confidence.compareTo(a.confidence))) {
    final l = t.label.toLowerCase();
    if (_generic.contains(l) || t.confidence < 0.5) continue;
    final fr = _labelToFrench[l];
    if (fr != null && !keywords.contains(fr)) keywords.add(fr);
    if (keywords.length == 4) break;
  }
  if (scores.isEmpty) return null;
  final top = scores.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  final confidence = best[top]!;
  if (confidence < kMinCategoryConfidence) return null;
  return CategorySuggestion(category: top, confidence: confidence, keywords: keywords);
}

/// Étiquettes à enregistrer avec l'article pour la recherche par photo :
/// minuscules, sans les termes trop vagues, confiance ≥ 0,5.
List<String> labelsForSearch(List<ImageTag> tags) {
  final out = <String>[];
  for (final t in tags) {
    final l = t.label.toLowerCase();
    if (t.confidence >= 0.5 && !_generic.contains(l) && !out.contains(l)) out.add(l);
  }
  return out;
}
