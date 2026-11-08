import 'dart:convert';

import 'package:campusconnect/models/conversation_model.dart';
import 'package:campusconnect/services/ai/chat_assistant.dart';
import 'package:campusconnect/services/ai/chat_replier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/articles.dart';
import '../helpers/fraud.dart';

http.Response _answer(String text) => http.Response.bytes(
      utf8.encode(jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': text},
              ],
            },
          },
        ],
      })),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  setUpAll(() => ChatIntentModel.cached = loadChatModel());

  final lamp = article('lamp',
      title: 'Lampe de bureau',
      description: 'Très bon état, ampoule LED neuve.',
      price: 25,
      category: 'Mobilier');
  ChatReplyRequest ask(String q) => ChatReplyRequest(
        question: q,
        article: lamp,
        sellerName: 'Amel',
        buyerId: 'bob',
        history: [
          ChatMessage(id: '1', senderId: 'bob', text: 'Bonjour', sentAt: DateTime(2026, 11, 8)),
          ChatMessage(id: '2', senderId: kAssistantId, text: 'Bonjour !', sentAt: DateTime(2026, 11, 8)),
        ],
      );

  test('Gemini gets the article, the conversation and the question, and its answer is used', () async {
    late Map<String, dynamic> body;
    late http.Request sent;
    final replier = GeminiChatReplier(
      apiKey: 'cle-test',
      model: 'gemini-test',
      backupModels: const [],
      client: MockClient((r) async {
        sent = r;
        body = jsonDecode(r.body) as Map<String, dynamic>;
        return _answer('  Oui, la lampe est toujours disponible, on se voit à la bibliothèque ?  ');
      }),
    );
    final text = await replier.reply(ask('mazel?'));
    expect(text, 'Oui, la lampe est toujours disponible, on se voit à la bibliothèque ?');
    expect(sent.headers['x-goog-api-key'], 'cle-test');
    expect(sent.url.path, endsWith('/models/gemini-test:generateContent'));
    final prompt = (((body['contents'] as List).first as Map)['parts'] as List).first['text'] as String;
    expect(prompt, contains('Lampe de bureau'));
    expect(prompt, contains('25 DT'));
    expect(prompt, contains('Statut : disponible'));
    expect(prompt, contains('Acheteur : Bonjour'));
    expect(prompt, contains('Assistant : Bonjour !'));
    expect(prompt, contains('Nouveau message de l\'acheteur : mazel?'));
    expect(prompt, contains('Ne promets jamais une baisse de prix'));
  });

  test('without a key, the embedded model answers (no network call)', () async {
    var calls = 0;
    final replier = GeminiChatReplier(
      apiKey: '',
      client: MockClient((_) async {
        calls++;
        return _answer('x');
      }),
    );
    expect(await replier.reply(ask('C\'est combien ?')), 'Le prix de « Lampe de bureau » est de 25 DT.');
    expect(calls, 0);
  });

  test('a Gemini error or an empty answer falls back to the embedded model', () async {
    for (final response in [http.Response('{"error":{"code":503}}', 503), _answer('')]) {
      final replier = GeminiChatReplier(
        apiKey: 'k',
        backupModels: const ['backup'],
        client: MockClient((_) async => response),
      );
      expect(await replier.reply(ask('Toujours dispo ?')), 'Oui, « Lampe de bureau » est toujours disponible.');
    }
  });
}
