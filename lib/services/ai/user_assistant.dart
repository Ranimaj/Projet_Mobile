import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../../models/user_model.dart';
import 'gemini_api_writer.dart';

/// Écran de l'app vers lequel l'assistant peut envoyer l'utilisateur.
enum AssistantAction {
  editProfile('Modifier mon profil'),
  studentCard('Ma carte étudiant'),
  verifyPhone('Vérifier mon numéro'),
  changePassword('Changer le mot de passe'),
  exportData('Exporter mes données');

  const AssistantAction(this.label);
  final String label;
}

/// Une étape de la checklist « profil complet ».
class ProfileStep {
  final String label;
  final bool done;

  /// Écran où faire l'étape ; `null` quand c'est un simple interrupteur du
  /// profil (double authentification).
  final AssistantAction? action;
  const ProfileStep(this.label, this.done, [this.action]);
}

/// État du profil : ce qui est fait, ce qui manque, et le score en %.
class ProfileHealth {
  final List<ProfileStep> steps;
  const ProfileHealth(this.steps);

  factory ProfileHealth.of(AppUser user) {
    final cardOk = user.isVerifiedStudent || user.studentCard.status == StudentCardStatus.verified;
    return ProfileHealth([
      ProfileStep('Photo de profil', (user.photoUrl ?? '').isNotEmpty, AssistantAction.editProfile),
      ProfileStep('Filière et année', (user.major ?? '').isNotEmpty && (user.year ?? '').isNotEmpty,
          AssistantAction.editProfile),
      ProfileStep('Au moins une compétence', user.skills.isNotEmpty, AssistantAction.editProfile),
      ProfileStep('Carte étudiant vérifiée', cardOk, AssistantAction.studentCard),
      ProfileStep('Téléphone vérifié', user.isPhoneVerified, AssistantAction.verifyPhone),
      ProfileStep('Double authentification', user.twoFactorEnabled),
    ]);
  }

  List<ProfileStep> get missing => [for (final s in steps) if (!s.done) s];
  int get percent => steps.isEmpty ? 100 : (100 * (steps.length - missing.length) / steps.length).round();
}

/// Un message de la conversation avec l'assistant.
class AssistantMessage {
  final bool fromUser;
  final String text;
  final List<AssistantAction> actions;
  const AssistantMessage.user(this.text)
      : fromUser = true,
        actions = const [];
  const AssistantMessage.bot(this.text, {this.actions = const []}) : fromUser = false;
}

/// Ce que l'assistant sait au moment de répondre.
class AssistantRequest {
  final String question;
  final AppUser user;
  final bool emailVerified;

  /// Messages précédents (le plus récent à la fin).
  final List<AssistantMessage> history;

  const AssistantRequest({
    required this.question,
    required this.user,
    this.emailVerified = true,
    this.history = const [],
  });

  String get firstName => user.fullName.trim().split(RegExp(r'\s+')).first;

  /// Consignes données au LLM : rôle, règles, et l'état du compte.
  String get systemPrompt {
    final u = user;
    final health = ProfileHealth.of(u);
    final card = switch (u.studentCard.status) {
      StudentCardStatus.none => 'pas encore envoyée',
      StudentCardStatus.pending => 'envoyée, en attente de vérification par un admin',
      StudentCardStatus.verified => 'vérifiée',
      StudentCardStatus.rejected =>
        'refusée${u.studentCard.rejectReason == null ? '' : ' (motif : ${u.studentCard.rejectReason})'}',
    };
    return '''
Tu es l'assistant de CampusConnect, l'application des étudiants d'ESPRIT (Tunisie) : annonces,
vente et don d'objets, événements, stages et emplois. Tu aides $firstName à utiliser l'app et à
gérer son compte.

Règles :
- 1 à 4 phrases courtes, ton amical, tutoiement, au plus un emoji.
- Réponds dans la langue de l'utilisateur (français, anglais, ou darija tunisienne en lettres
  latines s'il l'utilise).
- Base-toi sur l'état du compte ci-dessous et sur le fonctionnement de l'app. N'invente aucune
  fonctionnalité. Si tu ne sais pas, dis-le et propose de contacter l'administration.
- Ne demande jamais de mot de passe, de code reçu par SMS ni de donnée bancaire.
- Pour changer quelque chose, explique où aller dans l'app (onglet Profil).

Fonctionnement de l'app (onglet Profil) :
- « Modifier mes informations » : photo, nom, filière, année, compétences, campus.
- « Carte étudiant » : envoyer une photo de la carte ; un admin la vérifie, le badge
  « Étudiant vérifié » apparaît ensuite.
- « Numéro de téléphone » : vérification par code SMS.
- Sécurité : double authentification, connexion biométrique, changement de mot de passe.
- Données : export RGPD en JSON, suppression définitive du compte.
- Thème clair / sombre ; mode hors-ligne : les actions sont envoyées au retour du réseau.

État du compte de $firstName :
- Nom : ${u.fullName} ; e-mail ${emailVerified ? 'vérifié' : 'NON vérifié'}
- Filière : ${u.major ?? '(vide)'} ; année : ${u.year ?? '(vide)'} ; campus : ${u.campus}
- Compétences : ${u.skills.isEmpty ? '(aucune)' : u.skills.join(', ')}
- Carte étudiant : $card
- Téléphone : ${u.isPhoneVerified ? 'vérifié' : 'non vérifié'}
- Double authentification : ${u.twoFactorEnabled ? 'activée' : 'désactivée'}
- Profil complet à ${health.percent} %${health.missing.isEmpty ? '' : ' ; il manque : ${health.missing.map((s) => s.label).join(', ')}'}
''';
  }
}

/// Répond aux questions de l'utilisateur sur l'app et son compte.
abstract class UserAssistant {
  Future<AssistantMessage> reply(AssistantRequest request);
}

/// Sujets reconnus par l'assistant hors-ligne.
enum _Topic {
  greeting,
  thanks,
  profile,
  card,
  phone,
  password,
  security,
  email,
  data,
  deleteAccount,
  theme,
  offline,
  modules,
}

const Map<_Topic, List<String>> _keywords = {
  _Topic.greeting: ['bonjour', 'salut', 'hello', 'hi', 'coucou', 'aslema', 'ahla', 'salam'],
  _Topic.thanks: ['merci', 'thanks', 'thank', 'yaatik', 'sahit'],
  _Topic.profile: ['profil', 'profile', 'compléter', 'completer', 'photo', 'filière', 'filiere', 'compétence', 'competence', 'skill', 'nom', 'campus', 'modifier'],
  _Topic.card: ['carte', 'card', 'vérifié', 'verifie', 'badge', 'étudiant', 'etudiant', 'refus'],
  _Topic.phone: ['téléphone', 'telephone', 'phone', 'numéro', 'numero', 'sms', 'otp'],
  _Topic.password: ['mot de passe', 'password', 'mdp', 'oublié', 'oublie'],
  _Topic.security: ['sécurité', 'securite', 'security', '2fa', 'deux facteurs', 'double', 'biométri', 'biometri', 'empreinte', 'piraté', 'pirate', 'hack'],
  _Topic.email: ['email', 'e-mail', 'mail', 'courriel'],
  _Topic.data: ['données', 'donnees', 'data', 'rgpd', 'gdpr', 'export', 'confidentialité', 'privacy'],
  _Topic.deleteAccount: ['supprimer', 'suppression', 'delete', 'fermer mon compte', 'désinscri'],
  _Topic.theme: ['thème', 'theme', 'sombre', 'dark', 'clair', 'light', 'couleur'],
  _Topic.offline: ['hors-ligne', 'hors ligne', 'offline', 'réseau', 'reseau', 'internet', 'connexion', 'synchro'],
  _Topic.modules: ['vendre', 'vente', 'don', 'annonce', 'événement', 'evenement', 'event', 'stage', 'emploi', 'job', 'quoi faire', 'fonctionnalit', 'aide', 'help'],
};

/// Assistant **sans internet** : repère le sujet par mots-clés et répond
/// d'après l'état réel du compte (carte, téléphone, profil…).
class LocalUserAssistant implements UserAssistant {
  const LocalUserAssistant();

  /// Un mot-clé simple doit commencer un mot de la question (« hi » ne
  /// trouve pas « chiffre », mais « compétence » trouve « compétences ») ;
  /// une expression de plusieurs mots est cherchée telle quelle.
  static bool _matches(String q, List<String> words, String keyword) =>
      keyword.contains(' ') ? q.contains(keyword) : words.any((w) => w.startsWith(keyword));

  /// Sujets trouvés dans [question], du plus au moins pertinent (nombre de
  /// mots-clés trouvés, puis ordre de déclaration).
  static List<_Topic> _topics(String question) {
    final q = question.toLowerCase();
    final words = q.split(RegExp(r'[^a-z0-9à-ÿ-]+')).where((w) => w.isNotEmpty).toList();
    final scored = <_Topic, int>{};
    _keywords.forEach((topic, keys) {
      final hits = keys.where((k) => _matches(q, words, k)).length;
      if (hits > 0) scored[topic] = hits;
    });
    final list = scored.keys.toList()
      ..sort((a, b) => scored[b]!.compareTo(scored[a]!) != 0
          ? scored[b]!.compareTo(scored[a]!)
          : a.index.compareTo(b.index));
    // Une salutation suivie d'une vraie question : la question passe d'abord.
    if (list.length > 1) list.removeWhere((t) => t == _Topic.greeting || t == _Topic.thanks);
    return list;
  }

  /// Boutons d'action proposés pour [question] (même choix que la réponse).
  static List<AssistantAction> actionsFor(String question, AppUser user) {
    final topics = _topics(question);
    return topics.isEmpty ? const [] : _answer(topics.first, user, true).actions;
  }

  @override
  Future<AssistantMessage> reply(AssistantRequest request) async {
    final topics = _topics(request.question);
    if (topics.isEmpty) {
      return const AssistantMessage.bot(
        'Je n\'ai pas bien compris 🤔. Je peux t\'aider à compléter ton profil, faire vérifier ta '
        'carte étudiant, sécuriser ton compte ou gérer tes données. Essaie une des suggestions !',
      );
    }
    return _answer(topics.first, request.user, request.emailVerified, firstName: request.firstName);
  }

  static AssistantMessage _answer(_Topic topic, AppUser u, bool emailVerified, {String firstName = ''}) {
    final health = ProfileHealth.of(u);
    switch (topic) {
      case _Topic.greeting:
        final next = health.missing.isEmpty
            ? 'Ton profil est complet, bravo !'
            : 'Ton profil est complet à ${health.percent} % : il manque « ${health.missing.first.label} ».';
        return AssistantMessage.bot('Salut $firstName 👋 $next Pose-moi ta question.',
            actions: [
              if (health.missing.isNotEmpty && health.missing.first.action != null) health.missing.first.action!,
            ]);
      case _Topic.thanks:
        return const AssistantMessage.bot('Avec plaisir ! Je reste là si tu as une autre question.');
      case _Topic.profile:
        if (health.missing.isEmpty) {
          return const AssistantMessage.bot(
              'Ton profil est complet à 100 %. Tu peux toujours mettre à jour ta photo, ta filière ou tes '
              'compétences depuis « Modifier mes informations ».',
              actions: [AssistantAction.editProfile]);
        }
        final todo = health.missing.map((s) => s.label.toLowerCase()).join(', ');
        return AssistantMessage.bot(
          'Ton profil est complet à ${health.percent} %. Il te reste : $todo. Un profil complet inspire '
          'confiance aux acheteurs et aux recruteurs.',
          actions: {
            for (final s in health.missing)
              if (s.action != null) s.action!,
          }.toList(),
        );
      case _Topic.card:
        final cardOk = u.isVerifiedStudent || u.studentCard.status == StudentCardStatus.verified;
        if (cardOk) {
          return const AssistantMessage.bot(
              'Ta carte étudiant est vérifiée ✅ : le badge « Étudiant vérifié » s\'affiche sur ton profil.');
        }
        return switch (u.studentCard.status) {
          StudentCardStatus.pending => const AssistantMessage.bot(
              'Ta carte a bien été envoyée : un admin doit la vérifier. Tu verras le badge '
              '« Étudiant vérifié » dès qu\'elle sera acceptée.',
              actions: [AssistantAction.studentCard]),
          StudentCardStatus.rejected => AssistantMessage.bot(
              'Ta carte a été refusée${u.studentCard.rejectReason == null ? '' : ' (motif : ${u.studentCard.rejectReason})'}. '
              'Renvoie une photo nette, bien éclairée, où ton nom et ton numéro sont lisibles.',
              actions: const [AssistantAction.studentCard]),
          _ => const AssistantMessage.bot(
              'Tu n\'as pas encore envoyé ta carte étudiant. Prends-la en photo depuis « Carte étudiant » : '
              'un admin la vérifie et tu obtiens le badge « Étudiant vérifié ».',
              actions: [AssistantAction.studentCard]),
        };
      case _Topic.phone:
        return u.isPhoneVerified
            ? AssistantMessage.bot(
                'Ton numéro ${u.phoneNumber ?? ''} est déjà vérifié. Pour en changer, refais la vérification '
                'avec le nouveau numéro.',
                actions: const [AssistantAction.verifyPhone])
            : const AssistantMessage.bot(
                'Ton numéro n\'est pas encore vérifié. Saisis-le dans « Numéro de téléphone », puis entre le '
                'code reçu par SMS. Ne donne jamais ce code à quelqu\'un.',
                actions: [AssistantAction.verifyPhone]);
      case _Topic.password:
        return const AssistantMessage.bot(
            'Tu peux changer ton mot de passe depuis Profil › Compte. Si tu l\'as oublié, déconnecte-toi '
            'et utilise « Mot de passe oublié » sur l\'écran de connexion. Je ne te demanderai jamais ton '
            'mot de passe.',
            actions: [AssistantAction.changePassword]);
      case _Topic.security:
        final tips = [
          if (!u.twoFactorEnabled) 'active la double authentification (Profil › Sécurité)',
          if (!u.isPhoneVerified) 'vérifie ton numéro de téléphone',
          'active la connexion biométrique',
          'utilise un mot de passe unique',
        ];
        return AssistantMessage.bot(
          'Pour protéger ton compte : ${tips.join(', ')}. Si tu penses qu\'on a accès à ton compte, '
          'change ton mot de passe tout de suite.',
          actions: [
            if (!u.isPhoneVerified) AssistantAction.verifyPhone,
            AssistantAction.changePassword,
          ],
        );
      case _Topic.email:
        return AssistantMessage.bot(emailVerified
            ? 'Ton adresse ${u.email} est vérifiée. Elle ne peut pas être modifiée depuis l\'app.'
            : 'Ton adresse ${u.email} n\'est pas encore vérifiée : ouvre le lien reçu par e-mail '
                '(pense aux spams), ou renvoie-le depuis la bannière de ton profil.');
      case _Topic.data:
        return const AssistantMessage.bot(
            'Tu peux télécharger une copie de toutes tes données (format JSON) depuis Profil › '
            'Données & confidentialité. Tes données ne sont jamais vendues.',
            actions: [AssistantAction.exportData]);
      case _Topic.deleteAccount:
        return const AssistantMessage.bot(
            'Tu peux supprimer ton compte depuis Profil › Données & confidentialité › « Supprimer mon '
            'compte ». C\'est définitif : pense à exporter tes données avant.',
            actions: [AssistantAction.exportData]);
      case _Topic.theme:
        return const AssistantMessage.bot(
            'Change le thème (clair, sombre ou comme le téléphone) depuis Profil › Thème.');
      case _Topic.offline:
        return const AssistantMessage.bot(
            'Sans réseau, l\'app reste utilisable : tes actions sont gardées sur le téléphone et envoyées '
            'automatiquement au retour de la connexion. Le nombre d\'actions en attente s\'affiche dans '
            'Profil › Sécurité.');
      case _Topic.modules:
        return const AssistantMessage.bot(
            'Sur CampusConnect tu peux : vendre ou donner des objets (Vente & Don), publier des annonces, '
            'découvrir les événements du campus, et trouver un stage ou un emploi. Tout est accessible '
            'depuis la barre du bas.');
    }
  }
}

/// Assistant **par internet** avec le LLM Gemini (même clé que le reste de
/// l'IA). Il voit l'état du compte et la conversation. Les boutons d'action
/// viennent toujours de l'analyse locale de la question : ils restent fiables
/// quoi que réponde le LLM. Sans clé, sans réseau ou en cas d'erreur,
/// [fallback] répond à sa place.
class GeminiUserAssistant implements UserAssistant {
  GeminiUserAssistant({
    required this.apiKey,
    this.model = kGeminiModel,
    this.backupModels = kGeminiBackupModels,
    http.Client? client,
    this.fallback = const LocalUserAssistant(),
    this.timeout = const Duration(seconds: 20),
  }) : _client = client ?? http.Client();

  final String apiKey;
  final String model;
  final List<String> backupModels;
  final UserAssistant fallback;
  final Duration timeout;
  final http.Client _client;

  static const int maxLength = 800;

  @override
  Future<AssistantMessage> reply(AssistantRequest request) async {
    if (apiKey.isEmpty) return fallback.reply(request);
    for (final m in [model, ...backupModels]) {
      try {
        var text = await _ask(request, m);
        if (text.isEmpty) continue;
        if (text.length > maxLength) text = '${text.substring(0, maxLength)}…';
        return AssistantMessage.bot(text,
            actions: LocalUserAssistant.actionsFor(request.question, request.user));
      } catch (e) {
        debugPrint('[Assistant] Gemini $m indisponible ($e).');
      }
    }
    return fallback.reply(request);
  }

  Future<String> _ask(AssistantRequest request, String m) async {
    final recent = request.history.length > 10
        ? request.history.sublist(request.history.length - 10)
        : request.history;
    final contents = [
      for (final msg in recent)
        {
          'role': msg.fromUser ? 'user' : 'model',
          'parts': [
            {'text': msg.text},
          ],
        },
      {
        'role': 'user',
        'parts': [
          {'text': request.question},
        ],
      },
    ];
    final response = await _client
        .post(
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$m:generateContent'),
          headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
          body: jsonEncode({
            'systemInstruction': {
              'parts': [
                {'text': request.systemPrompt},
              ],
            },
            'contents': contents,
            'generationConfig': {'temperature': 0.5, 'maxOutputTokens': 1024},
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
