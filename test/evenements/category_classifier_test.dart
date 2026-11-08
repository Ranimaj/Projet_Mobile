import 'dart:convert';
import 'dart:io';

import 'package:campusconnect/screens/evenements/category_classifier.dart';
import 'package:campusconnect/screens/evenements/category_classifier_loader.dart';
import 'package:campusconnect/screens/evenements/event_categories.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// Modèle minuscule pour tester le seuil et la correspondance des libellés.
Map<String, dynamic> _tinyModel({List<String>? classes}) => {
      'version': 1,
      'threshold': 0.45,
      'classes': classes ?? ['Sport', 'Hackathon'],
      'stopwords': ['de'],
      'intercepts': [0.0, 0.0],
      'terms': {
        'foot': [1.0, -3.0, 3.0], // « foot » seul → Hackathon à ~99,8 %
        'match': [1.0, 3.0, -3.0], // « match » seul → Sport à ~99,8 %
      },
    };

class _FailingBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => throw StateError('absent');
}

class _StringBundle extends CachingAssetBundle {
  final String content;
  _StringBundle(this.content);
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(utf8.encode(content));
}

void main() {
  final model = CategoryClassifier.fromJson(_readJson('assets/ml/category_model.json'));
  final golden = (jsonDecode(File('test/fixtures/category_golden.json').readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  group('parité avec ml/train.py (vecteurs de référence)', () {
    test('le fichier de référence n\'est pas vide', () => expect(golden, isNotEmpty));
    for (final g in golden) {
      test('« ${g['text']} »', () {
        final expected = (g['probs'] as List).map((v) => (v as num).toDouble()).toList();
        final actual = model.probabilities(g['text'] as String);
        expect(actual.length, expected.length);
        for (var k = 0; k < expected.length; k++) {
          expect(actual[k], closeTo(expected[k], 1e-3), reason: 'classe ${model.classes[k]}');
        }
      });
    }
  });

  group('normalisation et découpage', () {
    test('minuscules et accents retirés', () {
      expect(CategoryClassifier.normalize('ÉTÉ À Noël Ça Où Ñandú ÿ'), 'ete a noel ca ou nandu y');
    });
    test('marques combinantes séparées retirées (comme NFD en Python)', () {
      expect(CategoryClassifier.normalize('Conférence'), 'conference');
    });
    test('apostrophes : « l\'école d\'été » → mots courts retirés, bigramme des voisins', () {
      expect(model.features("l'école d'été"), ['ecole', 'ete', 'ecole_ete']);
    });
    test('tirets séparent les mots', () {
      expect(model.features('inter-classes'), ['inter', 'classes', 'inter_classes']);
    });
    test('œ est un séparateur (non décomposé par NFD)', () {
      expect(model.features('cœur'), ['ur']);
    });
    test('mots vides retirés AVANT les bigrammes', () {
      expect(model.features('Tournoi de football'), ['tournoi', 'football', 'tournoi_football']);
    });
  });

  group('suggest', () {
    test('accents et casse sans effet', () {
      final a = model.probabilities("Conférence sur l'intelligence artificielle");
      final b = model.probabilities("CONFERENCE SUR L’INTELLIGENCE ARTIFICIELLE");
      for (var k = 0; k < a.length; k++) {
        expect(b[k], closeTo(a[k], 1e-12));
      }
      expect(model.suggest('CONFÉRENCE', "sur l'INTELLIGENCE artificielle")?.category,
          EventCategories.conference);
    });
    test('titre + description : catégorie et probabilité maximale', () {
      final s = model.suggest('Tournoi de football', 'Match inter-classes au stade du campus');
      expect(s?.category, EventCategories.sport);
      expect(s!.probability, closeTo(0.97665, 1e-3)); // valeur Python
    });
    test('charabia → null', () => expect(model.suggest('Zzzz qqqq', 'wwww xxxx'), isNull));
    test('texte vide → null', () {
      expect(model.suggest('', ''), isNull);
      expect(model.suggest('   ', '\n'), isNull);
    });
    test('terme connu mais sous le seuil (« bilan » : 22,7 %) → null', () {
      expect(model.knownTermCount('bilan'), 1);
      expect(model.probabilities('bilan').reduce((a, b) => a > b ? a : b), lessThan(model.threshold));
      expect(model.suggest('Bilan', ''), isNull);
    });
  });

  group('correspondance des libellés', () {
    test('chaque classe du modèle est une catégorie de la liste déroulante', () {
      for (final c in model.classes) {
        expect(CategoryClassifier.categoryFor(c), isNotNull, reason: c);
        expect(EventCategories.all, contains(CategoryClassifier.categoryFor(c)));
      }
    });
    test('libellé inconnu → null, même très probable', () {
      final tiny = CategoryClassifier.fromJson(_tinyModel());
      final s = tiny.suggest('match', '');
      expect(s?.category, EventCategories.sport);
      expect(s!.probability, closeTo(0.99753, 1e-5));
      expect(tiny.probabilities('foot')[1], greaterThan(0.99));
      expect(tiny.suggest('foot', ''), isNull);
    });
  });

  group('modèle invalide', () {
    test('poids de longueur incorrecte → FormatException', () {
      final bad = _tinyModel()..['terms'] = {'foot': [1.0, 2.0]};
      expect(() => CategoryClassifier.fromJson(bad), throwsFormatException);
    });
    test('clé manquante → FormatException', () {
      expect(() => CategoryClassifier.fromJson(<String, dynamic>{}), throwsFormatException);
    });
  });

  group('chargeur', () {
    setUp(CategoryClassifierLoader.resetCache);
    tearDown(CategoryClassifierLoader.resetCache);

    test('asset absent → null, sans exception', () async {
      expect(await CategoryClassifierLoader.load(bundle: _FailingBundle()), isNull);
    });
    test('JSON invalide → null', () async {
      expect(await CategoryClassifierLoader.load(bundle: _StringBundle('{pas du json')), isNull);
    });
    test('chargé une seule fois (cache)', () async {
      final raw = File('assets/ml/category_model.json').readAsStringSync();
      final first = await CategoryClassifierLoader.load(bundle: _StringBundle(raw));
      final second = await CategoryClassifierLoader.load(bundle: _FailingBundle());
      expect(first, isNotNull);
      expect(identical(first, second), isTrue);
    });
  });
}
