import 'dart:convert';
import 'dart:io';

import 'package:campusconnect/core/utils/trust_score.dart';
import 'package:campusconnect/models/user_model.dart';
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

  group('seller trust', () {
    final now = DateTime(2026, 11, 9);
    TrustScore trust({bool verified = false, DateTime? since}) => TrustScore.of(
          AppUser(
            id: 's',
            fullName: 'Vendeur',
            email: 's@esprit.tn',
            createdAt: since ?? now,
            isVerifiedStudent: verified,
            isPhoneVerified: verified,
            twoFactorEnabled: verified,
          ),
          completedSales: verified ? 5 : 0,
          now: now,
        );
    FraudReport analyze(TrustScore? t) => model.analyze(
          title: 'iPhone 13',
          description: 'Bon état, chargeur inclus. On se voit au campus.',
          category: 'Électronique',
          price: 900,
          hasPhoto: true,
          sellerTrust: t,
        );

    test('a new unverified seller raises the risk and is named as a reason', () {
      final base = analyze(null);
      final risky = analyze(trust());
      expect(risky.probability, greaterThan(base.probability));
      expect(risky.reasons, contains('Vendeur récent et peu vérifié (score de confiance bas).'));
    });

    test('a long-time verified seller lowers the risk', () {
      final base = analyze(null);
      final trusted = analyze(trust(verified: true, since: DateTime(2024, 1, 1)));
      expect(trusted.probability, lessThan(base.probability));
      expect(trusted.reasons, isNot(contains(startsWith('Vendeur récent'))));
    });

    test('the shift is symmetric around a score of 50', () {
      expect(sellerTrustShift(0), closeTo(kSellerTrustWeight, 1e-9));
      expect(sellerTrustShift(50), 0);
      expect(sellerTrustShift(100), closeTo(-kSellerTrustWeight, 1e-9));
    });
  });
}
