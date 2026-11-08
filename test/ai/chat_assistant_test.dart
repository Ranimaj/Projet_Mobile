import 'dart:convert';
import 'dart:io';

import 'package:campusconnect/models/article_model.dart';
import 'package:campusconnect/services/ai/chat_assistant.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fraud.dart';
import '../helpers/articles.dart';

void main() {
  final model = loadChatModel();
  final assistant = ChatAssistant(model);
  final lamp = article('lamp',
      title: 'Lampe de bureau',
      description: 'Très bon état, ampoule LED neuve. Idéale pour réviser.',
      price: 25,
      category: 'Mobilier',
      imageUrls: const ['a.jpg', 'b.jpg']);

  test('the app computes exactly like the Python training script', () {
    final examples = jsonDecode(File('test/ai/chat_examples.json').readAsStringSync()) as List;
    expect(examples, hasLength(40));
    for (final e in examples.cast<Map<String, dynamic>>()) {
      final got = model.classify(e['message'] as String);
      expect(got.name, e['intent'], reason: e['message'] as String);
      expect(got.confidence, closeTo((e['confidence'] as num).toDouble(), 0.01), reason: e['message'] as String);
    }
  });

  test('understands French and Tunisian darija', () {
    expect(model.classify('Bonjour, la lampe est toujours disponible ?').name, 'disponible');
    expect(model.classify('mazel?').name, 'disponible');
    expect(model.classify('Combien tu veux pour la chaise ?').name, 'prix');
    expect(model.classify('9adech?').name, 'prix');
    expect(model.classify('tu peux faire 30 dt ?').name, 'negociation');
    expect(model.classify('Elle a des rayures ?').name, 'etat');
    expect(model.classify('On se voit demain à la cafétéria ?').name, 'lieu');
    expect(model.classify('Tu peux me l\'envoyer à Sousse ?').name, 'livraison');
    expect(model.classify('Je la prends !').name, 'reserver');
  });

  test('answers with the article information', () {
    expect(assistant.reply('Toujours dispo ?', lamp, sellerName: 'Amel'),
        'Oui, « Lampe de bureau » est toujours disponible.');
    expect(assistant.reply('C\'est combien ?', lamp, sellerName: 'Amel'),
        'Le prix de « Lampe de bureau » est de 25 DT.');
    expect(assistant.reply('Elle est en bon état ?', lamp, sellerName: 'Amel'),
        'D\'après l\'annonce : « Très bon état, ampoule LED neuve. »');
    expect(assistant.reply('Tu as d\'autres photos ?', lamp, sellerName: 'Amel'), contains('2 photos'));
    expect(assistant.reply('Tu livres ?', lamp, sellerName: 'Amel'), contains('Ne paie jamais à l\'avance'));
    expect(assistant.reply('Tu peux baisser ?', lamp, sellerName: 'Amel'), contains('Amel qui décide'));
  });

  test('a reserved, sold or free article changes the answer', () {
    expect(assistant.reply('Toujours dispo ?', lamp.copyWith(status: ArticleStatus.reserved), sellerName: 'Amel'),
        contains('réservé'));
    expect(assistant.reply('Toujours dispo ?', lamp.copyWith(status: ArticleStatus.done), sellerName: 'Amel'),
        contains('déjà été vendu'));
    final gift = article('gift', title: 'Pull', price: null);
    expect(assistant.reply('C\'est combien ?', gift, sellerName: 'Amel'), contains('gratuit'));
  });

  test('an off-topic question is left to the seller', () {
    expect(assistant.reply('tu supportes quelle équipe de foot', lamp, sellerName: 'Amel'),
        contains('Amel te répondra directement'));
  });
}
