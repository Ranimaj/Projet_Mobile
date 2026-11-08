import 'dart:convert';
import 'dart:io';

import 'package:campusconnect/services/ai/article_ai.dart';
import 'package:campusconnect/services/ai/gemini_api_writer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _request = DescriptionRequest(
  title: 'Calculatrice scientifique',
  category: 'Électronique',
  price: 35,
  keywords: ['calculatrice'],
);

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
  test('sends the prompt with the key and returns Gemini\'s text', () async {
    late http.Request sent;
    final writer = GeminiApiDescriptionWriter(
      apiKey: 'cle-test',
      model: 'gemini-test',
      client: MockClient((r) async {
        sent = r;
        return _answer('  Calculatrice en très bon état, idéale pour les examens.  ');
      }),
    );
    final text = await writer.write(_request);
    expect(text, 'Calculatrice en très bon état, idéale pour les examens.');
    expect(sent.url.path, endsWith('/models/gemini-test:generateContent'));
    expect(sent.headers['x-goog-api-key'], 'cle-test');
    final body = jsonDecode(sent.body) as Map<String, dynamic>;
    final firstPart = ((body['contents'] as List).first as Map)['parts'][0] as Map;
    expect(firstPart['text'], contains('Calculatrice scientifique'));
  });

  test('the photo is sent as JPEG data when small enough', () async {
    final dir = Directory.systemTemp.createTempSync('gemini_photo');
    addTearDown(() => dir.deleteSync(recursive: true));
    final photo = File('${dir.path}/p.jpg')..writeAsBytesSync([1, 2, 3]);
    late Map<String, dynamic> body;
    final writer = GeminiApiDescriptionWriter(
      apiKey: 'k',
      client: MockClient((r) async {
        body = jsonDecode(r.body) as Map<String, dynamic>;
        return _answer('Texte');
      }),
    );
    await writer.write(DescriptionRequest(title: 'Lampe', category: 'Mobilier', photo: photo));
    final parts = ((body['contents'] as List).first as Map)['parts'] as List;
    expect(parts, hasLength(2));
    expect((parts[1] as Map)['inline_data'], {'mime_type': 'image/jpeg', 'data': base64Encode([1, 2, 3])});
  });

  test('without a key, the local writer is used (no network call)', () async {
    var calls = 0;
    final writer = GeminiApiDescriptionWriter(
      apiKey: '',
      client: MockClient((_) async {
        calls++;
        return _answer('x');
      }),
    );
    expect(await writer.write(_request), startsWith('Je vends calculatrice scientifique'));
    expect(calls, 0);
  });

  test('an error, an empty answer or no network falls back to the local writer', () async {
    final failing = [
      MockClient((_) async => http.Response('{"error":{"code":503}}', 503)),
      MockClient((_) async => http.Response('{"candidates":[]}', 200)),
      MockClient((_) async => throw const SocketException('pas de réseau')),
    ];
    for (final client in failing) {
      final text = await GeminiApiDescriptionWriter(apiKey: 'k', client: client).write(_request);
      expect(text, startsWith('Je vends calculatrice scientifique'));
    }
  });

  test('if the main model does not answer, the backup model is tried', () async {
    final asked = <String>[];
    final writer = GeminiApiDescriptionWriter(
      apiKey: 'k',
      model: 'lent',
      backupModels: const ['rapide'],
      client: MockClient((r) async {
        asked.add(r.url.pathSegments.last);
        if (r.url.path.contains('lent')) return http.Response('{"error":{"code":503}}', 503);
        return _answer('Réponse du modèle de secours.');
      }),
    );
    expect(await writer.write(_request), 'Réponse du modèle de secours.');
    expect(asked, ['lent:generateContent', 'rapide:generateContent']);
  });

  test('a very long answer is clipped to 1000 characters', () async {
    final writer = GeminiApiDescriptionWriter(apiKey: 'k', client: MockClient((_) async => _answer('a' * 1500)));
    expect((await writer.write(_request)).length, 1000);
  });
}
