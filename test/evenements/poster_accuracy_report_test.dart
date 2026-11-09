import 'dart:convert';
import 'dart:io';

import 'package:campusconnect/screens/evenements/category_classifier.dart';
import 'package:campusconnect/screens/evenements/poster_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'poster_fixtures.dart';

/// Rapport de précision des RÈGLES d'extraction, en deux parties :
///
/// 1. « lignes propres » : les 5 affiches de référence, texte idéal ;
/// 2. « observé sur émulateur » : le découpage en lignes que la lecture réelle
///    a produit (champs répartis sur plusieurs lignes, accent perdu) ; les
///    hauteurs et écarts sont estimés, faute de journal de l'émulateur.
///
/// Dans les deux cas, ce qui est mesuré, ce sont les règles appliquées à des
/// lignes de texte données. La qualité de la lecture d'une NOUVELLE photo
/// (flou, reflets, polices décoratives) n'est pas mesurée ici.
///
/// Lancer : flutter test test/evenements/poster_accuracy_report_test.dart
void main() {
  final classifier = CategoryClassifier.fromJson(
      jsonDecode(File('assets/ml/category_model.json').readAsStringSync()) as Map<String, dynamic>);
  const fields = ['titre', 'début', 'fin', 'lieu', 'prix'];

  /// Tableau d'une série d'affiches ; renvoie le texte et le nombre de champs justes.
  (String, Map<String, int>) table(String heading, List<PosterFixture> fixtures) {
    final correct = {for (final f in fields) f: 0};
    var categoryCorrect = 0;
    final rows = <String>[];
    for (final fx in fixtures) {
      final d = PosterParser.parse(fx.ocr, posterNow);
      final ok = {
        'titre': d.title == fx.title,
        'début': d.start == fx.start,
        'fin': d.end == fx.end,
        'lieu': d.place == fx.place,
        'prix': d.priceTnd == fx.price && d.isFree == fx.free,
      };
      ok.forEach((k, v) => correct[k] = correct[k]! + (v ? 1 : 0));
      final suggestion = classifier.suggest(d.title ?? '', d.description ?? '');
      final categoryOk = suggestion?.category == fx.category;
      if (categoryOk) categoryCorrect++;
      final percent = suggestion == null ? '—' : '${(suggestion.probability * 100).round()} %';
      final category = '${suggestion?.category ?? 'aucune'} ($percent)';
      rows.add('| ${fx.file.padRight(34)} | ${fields.map((f) => (ok[f]! ? 'ok' : 'FAUX').padRight(5)).join(' | ')} | '
          '${category.padRight(22)}${categoryOk ? '' : ' attendu : ${fx.category}'} |');
    }
    final n = fixtures.length;
    final out = StringBuffer()
      ..writeln(heading)
      ..writeln()
      ..writeln('| ${'Affiche'.padRight(34)} | ${fields.map((f) => f.padRight(5)).join(' | ')} | ${'Catégorie suggérée'.padRight(22)} |')
      ..writeln('|${'-' * 36}|${List.filled(fields.length, '-' * 7).join('|')}|${'-' * 24}|');
    rows.forEach(out.writeln);
    out.writeln('| ${'Total'.padRight(34)} | ${fields.map((f) => '${correct[f]}/$n'.padRight(5)).join(' | ')} | '
        '${'$categoryCorrect/$n'.padRight(22)} |');
    return (out.toString(), correct);
  }

  test('rapport de précision des règles (lignes propres et lignes observées sur émulateur)', () {
    final clean = table('1. Lignes propres (5 affiches de référence, texte idéal)', posterFixtures);
    final synthetic = table(
        '3. Affiches synthétiques (sans lien avec les 5 affiches : règles générales)', syntheticPosterFixtures);
    final observed = table(
        '2. Observé sur émulateur (découpage en lignes et accent perdu observés ; hauteurs et écarts estimés)',
        observedPosterFixtures);

    final out = StringBuffer()
      ..writeln()
      ..writeln("Précision des règles d'extraction des affiches")
      ..writeln('Les deux parties évaluent les RÈGLES sur des lignes de texte données ;')
      ..writeln("elles ne mesurent pas la lecture d'une nouvelle photo (flou, reflets, polices).")
      ..writeln()
      ..writeln(clean.$1)
      ..writeln(observed.$1)
      ..writeln(synthetic.$1);
    // ignore: avoid_print
    print(out);

    expect(clean.$2.values.every((v) => v == posterFixtures.length), isTrue, reason: 'régression :\n$out');
    expect(observed.$2.values.every((v) => v == observedPosterFixtures.length), isTrue,
        reason: 'régression :\n$out');
    expect(synthetic.$2.values.every((v) => v == syntheticPosterFixtures.length), isTrue,
        reason: 'régression :\n$out');
  });
}
