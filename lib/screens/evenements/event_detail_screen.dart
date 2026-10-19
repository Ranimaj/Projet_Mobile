import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/event_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/event_provider.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/status_badge.dart';
import 'add_event_screen.dart';
import 'event_rules.dart';
import 'event_validators.dart';

/// Détail d'un événement : informations, inscription, et pour
/// l'organisateur ou l'admin : modifier, annuler, supprimer.
/// (Le menu organisateur complet arrive à l'étape 8.)
class EventDetailScreen extends StatelessWidget {
  final EventModel event;
  const EventDetailScreen({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    // On relit l'événement dans le provider à chaque rebuild : après une
    // inscription, le provider recharge et l'écran affiche la nouvelle version.
    // Repli sur l'objet reçu si l'événement n'est plus dans la liste.
    final provider = context.watch<EventProvider>();
    final event = provider.findById(this.event.id) ?? this.event;
    final auth = context.watch<AuthProvider>();
    final isGuest = auth.status != AuthStatus.authenticated;
    final userId = auth.currentUser?.id;
    final isOwner = userId != null && userId == event.organizerId;
    final isAdmin = auth.currentUser?.role == UserRole.admin;
    final isRegistered = userId != null && event.isUserRegistered(userId);
    final isBusy = provider.isRegistrationBusy(event.id);
    final now = DateTime.now();
    final status = event.statusAt(now);
    final isCancelled = status == EventDisplayStatus.cancelled;

    // Raison pour laquelle le bouton est désactivé (null = action possible).
    final blockedReason = isRegistered
        ? EventRules.unregistrationBlocked(event, userId, now)
        : EventRules.registrationBlocked(event, userId, now);
    final capacityText = event.capacity == null
        ? '${event.registeredUserIds.length} inscrit(s)'
        : '${event.registeredUserIds.length} / ${event.capacity} inscrits';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Événement'),
        actions: [
          if (isOwner || isAdmin) ...[
            IconButton(
              tooltip: 'Modifier',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () {
                // Terminé ou annulé : on explique au lieu d'ouvrir le formulaire.
                final blocked = EventValidators.editBlocked(event, DateTime.now());
                if (blocked != null) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(blocked)));
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => AddEventScreen(existing: event)),
                );
              },
            ),
            if (EventRules.cancelBlocked(event, now) == null)
              IconButton(
                tooltip: "Annuler l'événement",
                icon: const Icon(Icons.event_busy_outlined),
                onPressed: () => _cancelEvent(context, event),
              ),
            IconButton(
              tooltip: 'Supprimer',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _deleteEvent(context, event, isAdmin: isAdmin),
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 140,
              decoration: BoxDecoration(
                gradient: AppColors.heroGradient,
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.celebration_outlined, size: 48, color: Colors.white),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                StatusBadge.info(event.category.toUpperCase()),
                if (isCancelled) StatusBadge.danger('ANNULÉ'),
                if (status == EventDisplayStatus.finished) StatusBadge.warning('TERMINÉ'),
                if (status == EventDisplayStatus.ongoing) StatusBadge.success('EN COURS'),
                if (status == EventDisplayStatus.full) StatusBadge.warning('COMPLET'),
                if (isRegistered && !isCancelled) StatusBadge.success('INSCRIT'),
              ],
            ),
            if (isCancelled) ...[
              const SizedBox(height: 12),
              _CancelledBanner(event: event),
            ],
            const SizedBox(height: 10),
            Text(event.title, style: Theme.of(context).textTheme.displayMedium),
            const SizedBox(height: 10),
            _InfoRow(
              icon: Icons.calendar_today_outlined,
              text: '${DateFormat('EEEE d MMMM yyyy · HH:mm', 'fr_FR').format(event.startDate)}'
                  ' → ${DateFormat('HH:mm', 'fr_FR').format(event.endDate)}',
            ),
            const SizedBox(height: 6),
            _InfoRow(icon: Icons.place_outlined, text: event.location),
            const SizedBox(height: 6),
            _InfoRow(
                icon: Icons.people_alt_outlined,
                text: '$capacityText · Organisé par ${event.organizerName}'),
            const SizedBox(height: 18),
            Text('Description', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(event.description, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6)),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () async {
                final link = context.read<EventProvider>().buildCalendarLink(event);
                await Clipboard.setData(ClipboardData(text: link));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Lien Google Calendar copié — collez-le dans votre navigateur.'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.event_available_outlined, size: 18),
              label: const Text('Ajouter à mon calendrier'),
            ),
            const SizedBox(height: 12),
            if (!isGuest && userId != null) ...[
              PrimaryButton(
                label: blockedReason == null
                    ? (isRegistered ? "Annuler l'inscription" : "S'inscrire à l'événement")
                    : _closedLabel(status, isRegistered),
                icon: isRegistered ? Icons.close_rounded : Icons.check_circle_outline_rounded,
                gradient: isRegistered ? AppColors.accentGradient : AppColors.primaryGradient,
                isLoading: isBusy, // le bouton ignore les taps pendant l'envoi
                // Désactivé (gris) quand l'action est impossible.
                onPressed: blockedReason == null ? () => _toggleRegistration(context, event, userId) : null,
              ),
              if (blockedReason != null) ...[
                const SizedBox(height: 8),
                Text(blockedReason, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ] else
              Text('Connectez-vous pour vous inscrire à cet événement.',
                  style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  /// Libellé court du bouton désactivé.
  static String _closedLabel(EventDisplayStatus status, bool isRegistered) {
    switch (status) {
      case EventDisplayStatus.cancelled:
        return 'Événement annulé';
      case EventDisplayStatus.finished:
        return 'Événement terminé';
      case EventDisplayStatus.ongoing:
        return 'Inscriptions closes';
      case EventDisplayStatus.full:
        return 'Complet';
      case EventDisplayStatus.upcoming:
        return isRegistered ? 'Désinscription impossible' : 'Inscription impossible';
    }
  }

  /// Inscription / désinscription, avec l'avertissement de conflit d'horaire
  /// (règle 3) avant une inscription.
  Future<void> _toggleRegistration(BuildContext context, EventModel event, String userId) async {
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<EventProvider>();

    if (!event.isUserRegistered(userId)) {
      final conflict = EventRules.findConflict(event, provider.all, userId, DateTime.now());
      if (conflict != null) {
        final goOn = await _confirm(
          context,
          title: "Conflit d'horaire",
          message: "Conflit d'horaire avec « ${conflict.title} ». S'inscrire quand même ?",
          confirmLabel: "S'inscrire",
        );
        if (!goOn) return;
      }
    }

    try {
      final registered = await provider.toggleRegistration(event, userId);
      if (registered == null) return; // tap ignoré, une requête est déjà en cours
      messenger.showSnackBar(SnackBar(
        content: Text(registered ? 'Inscription confirmée !' : 'Désinscription effectuée.'),
      ));
    } on EventActionException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.message),
        action: SnackBarAction(
          label: 'Réessayer',
          onPressed: () {
            if (context.mounted) _toggleRegistration(context, event, userId);
          },
        ),
      ));
    }
  }

  /// Annulation (règle 6) : motif obligatoire, puis envoi.
  Future<void> _cancelEvent(BuildContext context, EventModel event) async {
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<EventProvider>();
    final reason = await showDialog<String>(context: context, builder: (_) => const _CancelDialog());
    if (reason == null) return;
    try {
      final sentOnline = await provider.cancelEvent(event, reason);
      messenger.showSnackBar(SnackBar(
        content: Text(sentOnline
            ? 'Événement annulé. Les inscrits le verront comme annulé.'
            : 'Annulation enregistrée : envoi au retour du réseau.'),
      ));
    } on EventActionException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Suppression (règle 7) : toujours confirmée ; refusée à l'organisateur
  /// s'il y a des inscrits, avec la proposition d'annuler à la place.
  Future<void> _deleteEvent(BuildContext context, EventModel event, {required bool isAdmin}) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final provider = context.read<EventProvider>();

    final blocked = EventRules.deleteBlocked(event, isAdmin: isAdmin);
    if (blocked != null) {
      await _offerCancelInstead(context, event, blocked);
      return;
    }
    final n = event.registeredUserIds.length;
    final confirmed = await _confirm(
      context,
      title: "Supprimer l'événement ?",
      message: n == 0
          ? 'Cette action est définitive.'
          : 'Modération : $n personne(s) inscrite(s). Cette action est définitive.',
      confirmLabel: 'Supprimer',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await provider.deleteEvent(event, isAdmin: isAdmin);
      messenger.showSnackBar(const SnackBar(content: Text('Événement supprimé.')));
      navigator.pop();
    } on EventHasRegistrantsException catch (e) {
      // Quelqu'un s'est inscrit entre-temps.
      if (context.mounted) await _offerCancelInstead(context, event, e.message);
    } on EventActionException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _offerCancelInstead(BuildContext context, EventModel event, String message) async {
    final cancelInstead = await _confirm(
      context,
      title: 'Suppression impossible',
      message: message,
      confirmLabel: "Annuler l'événement",
      cancelLabel: 'Fermer',
    );
    if (cancelInstead && context.mounted) await _cancelEvent(context, event);
  }

  static Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    String cancelLabel = 'Annuler',
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(cancelLabel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: destructive ? TextButton.styleFrom(foregroundColor: AppColors.danger) : null,
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }
}

/// Bandeau rouge d'un événement annulé, avec le motif.
class _CancelledBanner extends StatelessWidget {
  final EventModel event;
  const _CancelledBanner({required this.event});

  @override
  Widget build(BuildContext context) {
    final when = event.cancelledAt == null
        ? ''
        : ' le ${DateFormat('d MMMM à HH:mm', 'fr_FR').format(event.cancelledAt!)}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        border: Border.all(color: AppColors.danger),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Événement annulé$when.\nMotif : ${event.cancelReason ?? 'non précisé'}',
        style: const TextStyle(color: Color(0xFF991B1B), fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Boîte de dialogue d'annulation : motif de 5 à 200 caractères.
class _CancelDialog extends StatefulWidget {
  const _CancelDialog();

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Annuler l'événement ?"),
      content: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: TextFormField(
          controller: _reasonCtrl,
          autofocus: true,
          maxLength: 200,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: "Motif de l'annulation",
            helperText: 'Visible par les inscrits',
          ),
          validator: EventValidators.cancelReason,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Retour')),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          onPressed: () {
            if (_formKey.currentState!.validate()) Navigator.pop(context, _reasonCtrl.text);
          },
          child: const Text("Annuler l'événement"),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    );
  }
}
