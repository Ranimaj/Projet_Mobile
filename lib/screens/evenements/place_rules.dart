/// Règles PURES des suggestions de lieu (testables sans réseau).
class PlaceRules {
  PlaceRules._();

  /// Parties du libellé, dans l'ordre : nom, rue (ou quartier si pas de
  /// rue), ville, pays. Les valeurs vides sont ignorées, les doublons
  /// (« Ariana, Ariana ») retirés sans tenir compte des majuscules.
  static List<String> suggestionParts({
    String? name,
    String? street,
    String? district,
    String? city,
    String? country,
  }) {
    String? clean(String? s) {
      final t = s?.trim() ?? '';
      return t.isEmpty ? null : t;
    }

    final parts = <String>[];
    for (final p in [clean(name), clean(street) ?? clean(district), clean(city), clean(country)]) {
      if (p == null) continue;
      if (parts.any((existing) => existing.toLowerCase() == p.toLowerCase())) continue;
      parts.add(p);
    }
    return parts;
  }

  /// Libellé complet d'une suggestion : « ESPRIT, Rue …, Ariana, Tunisie ».
  static String formatSuggestionLabel({
    String? name,
    String? street,
    String? district,
    String? city,
    String? country,
  }) =>
      suggestionParts(name: name, street: street, district: district, city: city, country: country).join(', ');
}
