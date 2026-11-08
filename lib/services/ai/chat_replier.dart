import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../../models/article_model.dart';
import '../../models/conversation_model.dart';
import 'chat_assistant.dart';
import 'gemini_api_writer.dart';

/// Ce que l'assistant sait au moment de répondre à l'acheteur.
class ChatReplyRequest {
  final String question;
  final ArticleModel article;

  /// Prénom du vendeur.
  final String sellerName;

  /// Derniers messages de la conversation (le plus récent à la fin).
  final List<ChatMessage> history;

  /// Identifiant de l'acheteur (pour savoir qui a écrit quoi).
  final String buyerId;

  const ChatReplyRequest({
    required this.question,
    required this.article,
    required this.sellerName,
    required this.buyerId,
    this.history = const [],
  });

  String get prompt {
    final a = article;
    final status = switch (a.status) {
      ArticleStatus.available => 'disponible',
      ArticleStatus.reserved => 'réservé',
      ArticleStatus.done => a.isFree ? 'déjà donné' : 'déjà vendu',
    };
    final lines = [
      for (final m in history.length > 8 ? history.sublist(history.length - 8) : history)
        '${m.senderId == buyerId ? 'Acheteur' : m.senderId == kAssistantId ? 'Assistant' : 'Vendeur'} : ${m.text}',
    ];
    return '''
Tu es l'assistant IA de $sellerName, un étudiant qui vend ou donne un objet sur CampusConnect,
la marketplace des étudiants de son école en Tunisie. Tu réponds à l'acheteur à la place du
vendeur, tout de suite.

Règles :
- 1 à 3 phrases courtes, ton amical et poli, sans emoji.
- Réponds dans la langue de l'acheteur (français, ou darija tunisienne en lettres latines s'il
  l'utilise).
- Utilise uniquement les informations de l'annonce ci-dessous. N'invente rien. Si l'information
  manque, dis que $sellerName répondra directement dans la conversation.
- Ne promets jamais une baisse de prix ni une réservation : c'est $sellerName qui décide.
- La remise se fait en main propre sur le campus. Ne propose jamais de livraison ni de paiement à
  l'avance (D17, virement…). Ne donne aucun numéro, e-mail ou lien.

Annonce :
- Titre : ${a.title}
- Catégorie : ${a.category}
- Prix : ${a.isFree ? 'don gratuit' : a.priceLabel}
- Statut : $status
- Description : ${a.description.trim().isEmpty ? '(aucune)' : a.description.trim()}
- Photos : ${a.imageUrls.length}

${lines.isEmpty ? '' : 'Conversation jusqu\'ici :\n${lines.join('\n')}\n'}
Nouveau message de l'acheteur : $question

Réponds uniquement avec ta réponse à l'acheteur.''';
  }
}

/// Répond à l'acheteur dans une conversation.
abstract class ChatReplier {
  Future<String> reply(ChatReplyRequest request);
}

/// Réponse **sans internet** : modèle d'intentions embarqué
/// (`assets/models/chat_model.json`) + infos de l'annonce.
class EmbeddedChatReplier implements ChatReplier {
  const EmbeddedChatReplier();

  @override
  Future<String> reply(ChatReplyRequest request) async {
    final model = await ChatIntentModel.load();
    return ChatAssistant(model).reply(request.question, request.article, sellerName: request.sellerName);
  }
}

/// Réponse **par internet** avec le LLM Gemini de Google (même clé que la
/// rédaction de description). Il lit l'annonce et la conversation, puis
/// répond comme un assistant du vendeur. Sans clé, sans réseau ou en cas
/// d'erreur, le modèle embarqué ([fallback]) répond à sa place.
class GeminiChatReplier implements ChatReplier {
  GeminiChatReplier({
    required this.apiKey,
    this.model = kGeminiModel,
    this.backupModels = kGeminiBackupModels,
    http.Client? client,
    this.fallback = const EmbeddedChatReplier(),
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  final String apiKey;
  final String model;
  final List<String> backupModels;
  final ChatReplier fallback;
  final Duration timeout;
  final http.Client _client;

  @override
  Future<String> reply(ChatReplyRequest request) async {
    if (apiKey.isEmpty) {
      debugPrint('[IA chat] Pas de clé GEMINI_API_KEY : modèle embarqué.');
      return fallback.reply(request);
    }
    for (final m in [model, ...backupModels]) {
      try {
        final text = await _ask(request.prompt, m);
        if (text.isEmpty) continue;
        return text.length > ChatMessage.maxLength ? text.substring(0, ChatMessage.maxLength) : text;
      } catch (e) {
        debugPrint('[IA chat] Gemini $m indisponible ($e).');
      }
    }
    debugPrint('[IA chat] Gemini n\'a pas répondu : modèle embarqué.');
    return fallback.reply(request);
  }

  Future<String> _ask(String prompt, String m) async {
    final response = await _client
        .post(
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$m:generateContent'),
          headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': prompt},
                ],
              },
            ],
            'generationConfig': {'temperature': 0.4, 'maxOutputTokens': 1024},
          }),
        )
        .timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Gemini ${response.statusCode} ${utf8.decode(response.bodyBytes)}');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final candidates = json['candidates'] as List? ?? const [];
    if (candidates.isEmpty) return '';
    final content = (candidates.first as Map<String, dynamic>)['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List? ?? const [];
    return [
      for (final p in parts)
        if (p is Map && p['text'] is String) p['text'] as String,
    ].join().trim();
  }
}
