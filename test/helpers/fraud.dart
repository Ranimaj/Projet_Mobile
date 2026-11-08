import 'dart:convert';
import 'dart:io';

import 'package:campusconnect/services/ai/chat_assistant.dart';
import 'package:campusconnect/services/ai/fraud_detector.dart';

/// Le modèle anti-arnaque embarqué de l'app (assets/models/fraud_model.json).
FraudModel loadFraudModel() => FraudModel.fromJson(
    jsonDecode(File('assets/models/fraud_model.json').readAsStringSync()) as Map<String, dynamic>);

/// Le modèle de conversation embarqué de l'app (assets/models/chat_model.json).
ChatIntentModel loadChatModel() => ChatIntentModel.fromJson(
    jsonDecode(File('assets/models/chat_model.json').readAsStringSync()) as Map<String, dynamic>);
