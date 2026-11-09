import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_tokens.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/ai/gemini_api_writer.dart';
import '../../services/ai/user_assistant.dart';
import '../../widgets/round_icon_button.dart';
import '../security/devices_screen.dart';
import 'change_password_screen.dart';
import 'edit_profile_screen.dart';
import 'student_card_screen.dart';

/// Gestion des Utilisateurs — assistant de l'app. Il répond aux questions sur
/// le compte (profil, carte étudiant, sécurité, données…) d'après l'état réel
/// du profil, et propose des boutons qui ouvrent le bon écran.
/// LLM Gemini par internet, assistant par mots-clés sans internet.
class AssistantScreen extends StatefulWidget {
  /// Assistant utilisé (par défaut : Gemini, sinon local).
  final UserAssistant? assistant;

  /// Actions qui vivent sur l'écran Profil (vérifier le téléphone, exporter
  /// les données). Sans ce rappel, leurs boutons ne sont pas affichés.
  final void Function(AssistantAction action)? onProfileAction;

  const AssistantScreen({super.key, this.assistant, this.onProfileAction});

  /// Questions proposées sous forme de puces.
  static const suggestions = [
    'Comment compléter mon profil ?',
    'Où en est ma carte étudiant ?',
    'Comment sécuriser mon compte ?',
    'Que puis-je faire sur l\'app ?',
  ];

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  late final UserAssistant _assistant = widget.assistant ?? GeminiUserAssistant(apiKey: kGeminiApiKey);
  final _input = TextEditingController();
  final _messages = <AssistantMessage>[];
  bool _thinking = false;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().currentUser;
    if (user != null) _messages.add(_welcome(user));
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  AssistantMessage _welcome(AppUser user) {
    final firstName = user.fullName.trim().split(RegExp(r'\s+')).first;
    final missing = ProfileHealth.of(user).missing;
    final next = missing.isEmpty
        ? 'Ton profil est complet, bravo !'
        : 'Petit conseil : il te manque « ${missing.first.label} ».';
    return AssistantMessage.bot(
      'Salut $firstName 👋 Je suis l\'assistant CampusConnect. Je peux t\'aider avec ton profil, ta '
      'carte étudiant, la sécurité de ton compte ou tes données. $next',
      actions: [if (missing.isNotEmpty && missing.first.action != null) missing.first.action!],
    );
  }

  Future<void> _send([String? preset]) async {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    final question = (preset ?? _input.text).trim();
    if (user == null || question.isEmpty || _thinking) return;
    final history = List<AssistantMessage>.of(_messages.skip(1)); // sans l'accueil
    setState(() {
      _messages.add(AssistantMessage.user(question));
      _thinking = true;
    });
    _input.clear();
    AssistantMessage answer;
    try {
      answer = await _assistant.reply(AssistantRequest(
        question: question,
        user: user,
        emailVerified: auth.emailVerified,
        history: history,
      ));
    } catch (_) {
      answer = const AssistantMessage.bot('Oups, je n\'ai pas pu répondre. Réessaie dans un instant.');
    }
    if (!mounted) return;
    setState(() {
      _messages.add(answer);
      _thinking = false;
    });
  }

  bool _available(AssistantAction a) => switch (a) {
        AssistantAction.verifyPhone || AssistantAction.exportData => widget.onProfileAction != null,
        AssistantAction.changePassword => context.read<AuthProvider>().hasPasswordProvider,
        _ => true,
      };

  void _run(AssistantAction action) {
    final nav = Navigator.of(context);
    switch (action) {
      case AssistantAction.editProfile:
        nav.push(MaterialPageRoute<void>(builder: (_) => const EditProfileScreen()));
      case AssistantAction.studentCard:
        nav.push(MaterialPageRoute<void>(builder: (_) => const StudentCardScreen()));
      case AssistantAction.changePassword:
        nav.push(MaterialPageRoute<void>(builder: (_) => const ChangePasswordScreen()));
      case AssistantAction.devices:
        nav.push(MaterialPageRoute<void>(builder: (_) => const DevicesScreen()));
      case AssistantAction.verifyPhone:
      case AssistantAction.exportData:
        widget.onProfileAction?.call(action);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final user = context.watch<AuthProvider>().currentUser;
    final items = [..._messages.reversed];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: t.primarySoft,
              child: Icon(Icons.smart_toy_rounded, size: 20, color: t.primary),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Assistant', style: text.titleMedium),
                Text(_thinking ? 'écrit…' : 'Toujours disponible', style: text.labelMedium),
              ],
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (user != null) _ProfileProgress(health: ProfileHealth.of(user), onTap: _run, available: _available),
          Expanded(
            child: ListView.builder(
              key: const Key('assistant-messages'),
              reverse: true,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              itemCount: items.length + (_thinking ? 1 : 0),
              itemBuilder: (context, i) {
                if (_thinking && i == 0) return const _TypingBubble();
                final m = items[_thinking ? i - 1 : i];
                return _AssistantBubble(
                  message: m,
                  actions: [for (final a in m.actions) if (_available(a)) a],
                  onAction: _run,
                );
              },
            ),
          ),
          SingleChildScrollView(
            key: const Key('assistant-suggestions'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final s in AssistantScreen.suggestions)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      label: Text(s),
                      onPressed: _thinking ? null : () => _send(s),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              decoration: BoxDecoration(
                color: t.surface,
                border: Border(top: BorderSide(color: t.outline)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('assistant-input'),
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 500,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Pose ta question…',
                        counterText: '',
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  RoundIconButton(
                    key: const Key('assistant-send'),
                    icon: Icons.send_rounded,
                    tooltip: 'Envoyer',
                    style: RoundButtonStyle.primary,
                    size: 44,
                    onPressed: _thinking ? null : _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bandeau « profil complet à X % » avec les étapes qui manquent.
class _ProfileProgress extends StatelessWidget {
  final ProfileHealth health;
  final void Function(AssistantAction) onTap;
  final bool Function(AssistantAction) available;
  const _ProfileProgress({required this.health, required this.onTap, required this.available});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final done = health.missing.isEmpty;
    return Container(
      key: const Key('profile-progress'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: t.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Profil complet à ${health.percent} %', style: text.titleSmall)),
              if (done) Icon(Icons.verified_rounded, color: t.success, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: health.percent / 100,
              minHeight: 6,
              backgroundColor: t.surfaceMuted,
              color: done ? t.success : t.primary,
            ),
          ),
          if (!done) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in health.missing)
                  ActionChip(
                    avatar: Icon(Icons.add_circle_outline_rounded, size: 16, color: t.primary),
                    label: Text(s.label),
                    visualDensity: VisualDensity.compact,
                    onPressed: s.action != null && available(s.action!) ? () => onTap(s.action!) : null,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AssistantBubble extends StatelessWidget {
  final AssistantMessage message;
  final List<AssistantAction> actions;
  final void Function(AssistantAction) onAction;
  const _AssistantBubble({required this.message, required this.actions, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final mine = message.fromUser;
    final fg = mine ? t.onPrimary : t.textPrimary;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: mine ? t.primary : t.surfaceMuted,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(mine ? 18 : 4),
              bottomRight: Radius.circular(mine ? 4 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message.text, style: text.bodyLarge?.copyWith(color: fg)),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final a in actions)
                      FilledButton.tonal(
                        key: Key('assistant-action-${a.name}'),
                        style: FilledButton.styleFrom(
                          backgroundColor: t.primarySoft,
                          foregroundColor: t.onPrimarySoft,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => onAction(a),
                        child: Text(a.label),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const Key('assistant-typing'),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: t.surfaceMuted, borderRadius: BorderRadius.circular(18)),
        child: SizedBox(
          width: 36,
          height: 12,
          child: LinearProgressIndicator(
            borderRadius: BorderRadius.circular(6),
            backgroundColor: t.surfaceMuted,
            color: t.textSecondary.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}
