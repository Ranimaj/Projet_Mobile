/// SOURCE UNIQUE des catégories d'événements (pure Dart : utilisable par le
/// modèle, les validateurs et les tests). Couleurs et icônes : event_style.dart.
class EventCategories {
  EventCategories._();

  static const String conference = 'Conférence';
  static const String career = 'Carrière';
  static const String sport = 'Sport';
  static const String culture = 'Culture';
  static const String studentLife = 'Vie associative';

  /// Les 5 catégories acceptées à la création et à la modification.
  static const List<String> all = [conference, career, sport, culture, studentLife];

  /// Anciennes valeurs → nouvelles (anciens documents Firestore).
  static const Map<String, String> legacy = {
    'Job Fair': career,
    'Associatif': studentLife,
    'Générale': conference, // ancienne valeur par défaut de fromMap
  };

  /// Catégorie à afficher pour une valeur stockée : une valeur actuelle est
  /// gardée, une ancienne est traduite, une inconnue (ou absente) devient
  /// « Conférence ». Appliquée dans fromMap : aucune migration nécessaire.
  static String normalize(String? stored) {
    if (stored == null) return conference;
    if (all.contains(stored)) return stored;
    return legacy[stored] ?? conference;
  }
}
