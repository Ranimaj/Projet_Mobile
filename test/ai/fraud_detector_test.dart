import 'dart:convert';
import 'dart:io';

import 'package:campusconnect/services/ai/fraud_detector.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fraud.dart';

void main() {
  final model = loadFraudModel();

  test('the app computes exactly like the Python training script', () {
    final examples = jsonDecode(File('test/ai/fraud_examples.json').readAsStringSync()) as List;
    expect(examples, hasLength(40));
    for (final e in examples.cast<Map<String, dynamic>>()) {
      final p = model.probability(fraudFeatures(
        title: e['title'] as String,
        description: e['description'] as String,
        category: e['category'] as String,
        price: (e['price'] as num?)?.toDouble(),
        hasPhoto: e['hasPhoto'] as bool,
      ));
      expect(p, closeTo((e['probability'] as num).toDouble(), 0.002), reason: e['title'] as String);
    }
  });

  test('a normal campus listing is low risk', () {
    final r = model.analyze(
      title: 'Livre d\'algorithmique',
      description: 'Bon état, quelques notes au crayon. Remise en main propre à la bibliothèque du campus.',
      category: 'Livres',
      price: 15,
      hasPhoto: true,
    );
    expect(r.risk, FraudRisk.low);
    expect(r.percent, lessThan(30));
  });

  test('a classic scam is high risk and explains why', () {
    final r = model.analyze(
      title: 'iPhone 14 Pro neuf',
      description: 'Neuf sous blister. Paiement par virement avant l\'envoi, livraison seulement. '
          'Contactez-moi sur WhatsApp.',
      category: 'Électronique',
      price: 90,
      hasPhoto: false,
    );
    expect(r.risk, FraudRisk.high);
    expect(r.percent, greaterThan(90));
    expect(r.reasons, hasLength(3));
    expect(r.reasons.first, contains('paiement à l\'avance'));
  });

  test('one clue alone stays moderate at most', () {
    final r = model.analyze(
      title: 'Chaise de bureau',
      description: 'Bon état. Je déménage, c\'est urgent, on se voit sur le campus devant le bloc A.',
      category: 'Mobilier',
      price: 50,
      hasPhoto: true,
    );
    expect(r.risk, isNot(FraudRisk.high));
  });

  test('features: free but asks to pay, phone number, shouting', () {
    final f = fraudFeatures(
      title: 'DON GRATUIT',
      description: 'Juste les frais de livraison à payer. Appelez le 22 123 456 !!!',
      category: 'Autre',
      price: null,
      hasPhoto: true,
    );
    expect(f['free_but_pay'], 1);
    expect(f['payment'], 1);
    expect(f['off_app'], 1);
    expect(f['shouting'], 1);
    expect(f['price_far_below'], 0);
  });
}
