import 'dart:convert';
import 'dart:io';

import 'package:campusconnect/screens/evenements/category_classifier.dart';
import 'package:campusconnect/screens/evenements/poster_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'poster_fixtures.dart';

/// Rapport de précision des RÈGLES d'extraction sur les 5 affiches de
/// référence.
///
/// Ce qui est mesuré : les règles appliquées à des lignes de texte propres,
/// comme si la lecture de l'image était parfaite. Ce qui n'est PAS mesuré :
/// la qualité de la lecture de l'image elle-même (photo floue, police
/// décorative, reflets…). Sur une vraie photo, les résultats peuvent être
/// moins bons.
///
/// Lancer : flutter test test/evenements/poster_accuracy_report_test.dart
void main() {
  test('rapport de précision des règles (texte propre, sans lecture d\'image)', () {
    final classifier = CategoryClassifier.fromJson(
        jsonDecode(File('assets/ml/category_model.json').readAsStringSync()) as Map<String, dynamic>);

    const fields = ['titre', 'début', 'fin', 'lieu', 'prix'];
    final correct = {for (final f in fields) f: 0};
    var categoryCorrect = 0;
    final rows = <String>[];

    for (final fx in posterFixtures) {
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
      rows.add('| ${fx.file.padRight(24)} | ${fields.map((f) => (ok[f]! ? 'ok' : 'FAUX').padRight(5)).join(' | ')} | '
          '${category.padRight(22)}${categoryOk ? '' : ' attendu : ${fx.category}'} |');
    }

    final n = posterFixtures.length;
    final out = StringBuffer()
      ..writeln()
      ..writeln('Précision des règles d\'extraction — $n affiches de référence')
      ..writeln('Mesure faite sur des lignes de texte propres : elle évalue les règles,')
      ..writeln('PAS la lecture de l\'image (une vraie photo peut donner moins bien).')
      ..writeln()
      ..writeln('| ${'Affiche'.padRight(24)} | ${fields.map((f) => f.padRight(5)).join(' | ')} | ${'Catégorie suggérée'.padRight(22)} |')
      ..writeln('|${'-' * 26}|${List.filled(fields.length, '-' * 7).join('|')}|${'-' * 24}|');
    rows.forEach(out.writeln);
    out
      ..writeln('| ${'Total'.padRight(24)} | ${fields.map((f) => '${correct[f]}/$n'.padRight(5)).join(' | ')} | '
          '${'$categoryCorrect/$n'.padRight(22)} |')
      ..writeln();
    // ignore: avoid_print
    print(out);

    expect(correct.values.every((v) => v == n), isTrue, reason: 'une règle a régressé :\n$out');
  });
}
