import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/event_model.dart';
import '../../models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/event_provider.dart';
import '../../widgets/pill_button.dart';
import 'add_event_screen.dart';
import 'attendees_screen.dart';
import 'event_calendar_launcher.dart';
import 'event_calendar_sync.dart';
import 'event_map.dart';
import 'open_meteo_service.dart';
import 'weather_rules.dart';
import 'event_rules.dart';
import 'event_style.dart';
import 'event_validators.dart';
import 'ticket_rules.dart';
import 'ticket_screen.dart';

/// Actions du menu organisateur / admin.
enum _MenuAction { attendees, edit, cancel, delete }

/// Détail d'un événement (règles 5, 6, 7 et 10) : données EN DIRECT
/// (events/{id}.snapshots()), en-tête affiche ou couleur de catégorie,
/// cartes d'information, jauge de places, bandeau « Modifié le… », menu
/// organisateur et barre d'inscription fixée en bas.
class EventDetailScreen extends StatefulWidget {
  final EventModel event;
  const EventDetailScreen({super.key, required this.event});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  late final Stream<({EventModel? event, bool fromCache})> _live;

  /// Vrai quand l'écran se ferme volontairement (suppression) : évite de
  /// réagir une 2e fois au document supprimé dans le flux.
  bool _leaving = false;

  /// Barre d'inscription du bas : sa clé sert à mesurer sa hauteur réelle.
  final _barKey = GlobalKey();
  double _barHeight = 0;

  @override
  void initState() {
    super.initState();
    // Flux créé UNE fois (pas dans build, sinon on se réabonnerait à chaque rebuild).
    _live = context.read<EventProvider>().watchEvent(widget.event.id);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<({EventModel? event, bool fromCache})>(
      stream: _live,
      builder: (context, snapshot) {
        // Dernière copie connue (provider, sinon celle reçue) : utilisée
        // pendant le chargement, en cas d'erreur ou hors-ligne.
        final provider = context.watch<EventProvider>();
        final known = provider.findById(widget.event.id) ?? widget.event;
        final data = snapshot.data;

        if (data != null && data.event == null && !data.fromCache) {
          _onDeleted();
          return _buildContent(known, isLoading: false, isOffline: false);
        }
        final event = data?.event ?? known;
        final isLoading = snapshot.connectionState == ConnectionState.waiting && data == null;
        final isOffline = snapshot.hasError || (data?.fromCache ?? false);
        return _buildContent(event, isLoading: isLoading, isOffline: isOffline);
      },
    );
  }

  /// Document supprimé (par l'organisateur ou un admin, ailleurs) : on
  /// prévient et on revient en arrière, une seule fois.
  void _onDeleted() {
    if (_leaving) return;
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      final route = ModalRoute.of(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cet événement n'existe plus.")));
      // Ferme d'abord une éventuelle boîte de dialogue ouverte au-dessus.
      if (route != null) navigator.popUntil((r) => r == route);
      navigator.pop();
    });
  }

  Widget _buildContent(EventModel event, {required bool isLoading, required bool isOffline}) {
    final auth = context.watch<AuthProvider>();
    final userId = auth.currentUser?.id;
    final isOwner = userId != null && userId == event.organizerId;
    final isAdmin = auth.currentUser?.role == UserRole.admin;
    final isRegistered = userId != null && event.isUserRegistered(userId);
    final now = DateTime.now();
    final color = EventStyle.categoryColor(event.category);

    // Hauteur RÉELLE de la barre du bas (elle change : « Mon billet », motif
    // de refus, zone de sécurité…), mesurée après l'affichage.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _barKey.currentContext?.size?.height;
      if (mounted && h != null && (h - _barHeight).abs() > 0.5) setState(() => _barHeight = h);
    });

    return Scaffold(
      // Le contenu passe derrière la barre du bas, et on réserve en bas
      // exactement sa hauteur (zone de sécurité comprise) + une marge : la
      // carte et les derniers blocs ne sont jamais cachés.
      extendBody: true,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 280,
            backgroundColor: color, // couleur pleine une fois l'en-tête replié
            foregroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            actions: [
              if (isOwner || isAdmin) _organizerMenu(event, isAdmin: isAdmin, now: now),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _Header(event: event, now: now, isRegistered: isRegistered),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              // Avant la première mesure : une estimation de la barre (140 px).
              padding: EdgeInsets.fromLTRB(20, 16, 20, (_barHeight > 0 ? _barHeight : 140) + 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isLoading) ...[
                    const LinearProgressIndicator(minHeight: 2),
                    const SizedBox(height: 12),
                  ],
                  if (isOffline) ...[
                    const _OfflineNote(),
                    const SizedBox(height: 12),
                  ],
                  Text(event.title, style: Theme.of(context).textTheme.headlineSmall),
                  if (event.status == EventStatus.cancelled) ...[
                    const SizedBox(height: 12),
                    _CancelledBanner(event: event),
                  ],
                  if (EventRules.showModifiedBanner(event)) ...[
                    const SizedBox(height: 12),
                    _ModifiedBanner(updatedAt: event.updatedAt),
                  ],
                  const SizedBox(height: 16),
                  _QuickActions(
                    onCalendar: () => _addToCalendar(event),
                    calendarBlockedReason: EventCalendarSync.blockedReason(event),
                    onItinerary: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => EventMapScreen(event: event, showItinerary: true))),
                    // Sans coordonnées, pas de destination : on explique pourquoi.
                    itineraryBlockedReason: event.latitude == null || event.longitude == null
                        ? 'Lieu non localisé : itinéraire indisponible.'
                        : null,
                    onShare: () => _share(event),
                    shareBlockedReason: TicketRules.shareBlockedReason(event),
                  ),
                  const SizedBox(height: 16),
                  _InfoCard(
                    icon: Icons.calendar_today_outlined,
                    color: color,
                    title: _dateTitle(event),
                    subtitle: _timeSubtitle(event),
                  ),
                  // Météo prévue (cachée si hors-ligne, trop loin ou en cas d'échec).
                  _WeatherChip(event: event, isOnline: context.watch<EventProvider>().isOnline),
                  const SizedBox(height: 10),
                  _InfoCard(
                    icon: Icons.place_outlined,
                    color: color,
                    title: event.location,
                    // Sans coordonnées (lieu introuvable ou ajouté hors-ligne).
                    subtitle: event.latitude == null || event.longitude == null ? 'Lieu non localisé' : 'Lieu',
                  ),
                  if (event.latitude != null && event.longitude != null) ...[
                    const SizedBox(height: 10),
                    EventMapCard(event: event, isOnline: context.watch<EventProvider>().isOnline),
                  ],
                  const SizedBox(height: 10),
                  _InfoCard(
                      icon: Icons.person_outline_rounded,
                      color: color,
                      title: event.organizerName.isEmpty ? 'Organisateur inconnu' : event.organizerName,
                      subtitle: 'Organisateur'),
                  const SizedBox(height: 10),
                  _CapacityCard(event: event),
                  const SizedBox(height: 22),
                  Text('Description', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(event.description,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.6)),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: KeyedSubtree(
        key: _barKey,
        child: _buildRegisterBar(event, userId: userId, isRegistered: isRegistered, now: now),
      ),
    );
  }

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _dateTitle(EventModel e) => _capitalize(DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(e.startDate));

  /// « 14:00 → 16:00 · 2 h », avec la date de fin si elle tombe un autre jour.
  String _timeSubtitle(EventModel e) {
    final sameDay = EventRules.dateOnly(e.startDate) == EventRules.dateOnly(e.endDate);
    final end = sameDay
        ? DateFormat('HH:mm', 'fr_FR').format(e.endDate)
        : DateFormat('EEE d MMM HH:mm', 'fr_FR').format(e.endDate);
    return '${DateFormat('HH:mm', 'fr_FR').format(e.startDate)} → $end · '
        '${EventRules.durationLabel(e.startDate, e.endDate)}';
  }

  /// Partage texte (titre, date, lieu, prix, invitation), sans lien profond.
  /// Fonctionne hors-ligne : c'est l'appli choisie qui enverra le message.
  Future<void> _share(EventModel event) async {
    final messenger = ScaffoldMessenger.of(context);
    final blocked = TicketRules.shareBlockedReason(event);
    if (blocked != null) {
      messenger.showSnackBar(SnackBar(content: Text(blocked)));
      return;
    }
    try {
      await SharePlus.instance.share(ShareParams(text: TicketRules.shareMessage(event), subject: event.title));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Partage impossible sur cet appareil.')));
    }
  }

  /// BF9 : ouvre le calendrier du téléphone avec l'événement pré-rempli
  /// (vraies dates de début et de fin). L'utilisateur vérifie puis enregistre
  /// dans son application Calendrier.
  Future<void> _addToCalendar(EventModel event) async {
    final messenger = ScaffoldMessenger.of(context);
    final blocked = EventCalendarSync.blockedReason(event);
    if (blocked != null) {
      messenger.showSnackBar(SnackBar(content: Text(blocked)));
      return;
    }
    try {
      await EventCalendarLauncher.open(EventCalendarSync.buildEntry(event));
      final note = EventCalendarSync.note(event, DateTime.now());
      messenger.showSnackBar(SnackBar(
        content: Text(note ?? "Calendrier ouvert : vérifiez puis enregistrez l'événement."),
      ));
    } on EventActionException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  // ------------------------------------------------------- Menu organisateur

  Widget _organizerMenu(EventModel event, {required bool isAdmin, required DateTime now}) {
    final t = AppTokens.of(context);
    final canCancel = EventRules.cancelBlocked(event, now) == null;
    return PopupMenuButton<_MenuAction>(
      tooltip: 'Actions organisateur',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (action) {
        switch (action) {
          case _MenuAction.attendees:
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => AttendeesScreen(event: event)));
          case _MenuAction.edit:
            _edit(event);
          case _MenuAction.cancel:
            _cancelEvent(event);
          case _MenuAction.delete:
            _deleteEvent(event, isAdmin: isAdmin);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: _MenuAction.attendees,
          child: ListTile(leading: Icon(Icons.people_alt_outlined), title: Text('Participants')),
        ),
        const PopupMenuItem(
          value: _MenuAction.edit,
          child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Modifier')),
        ),
        PopupMenuItem(
          value: _MenuAction.cancel,
          enabled: canCancel,
          child: const ListTile(leading: Icon(Icons.event_busy_outlined), title: Text("Annuler l'événement")),
        ),
        PopupMenuItem(
          value: _MenuAction.delete,
          child: ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: t.danger),
            title: Text('Supprimer', style: TextStyle(color: t.danger)),
          ),
        ),
      ],
    );
  }

  void _edit(EventModel event) {
    // Terminé ou annulé : on explique au lieu d'ouvrir le formulaire.
    final blocked = EventValidators.editBlocked(event, DateTime.now());
    if (blocked != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(blocked)));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddEventScreen(existing: event)));
  }

  /// Annulation (règle 6) : motif obligatoire, puis envoi.
  Future<void> _cancelEvent(EventModel event) async {
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
  Future<void> _deleteEvent(EventModel event, {required bool isAdmin}) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final provider = context.read<EventProvider>();

    final blocked = EventRules.deleteBlocked(event, isAdmin: isAdmin);
    if (blocked != null) {
      await _offerCancelInstead(event, blocked);
      return;
    }
    final n = event.registeredUserIds.length;
    final confirmed = await _confirm(
      title: "Supprimer l'événement ?",
      message: n == 0
          ? 'Cette action est définitive.'
          : 'Modération : $n personne(s) inscrite(s). Cette action est définitive.',
      confirmLabel: 'Supprimer',
      destructive: true,
    );
    if (!confirmed) return;
    _leaving = true; // le flux va signaler la suppression : on ne veut pas fermer deux fois
    try {
      await provider.deleteEvent(event, isAdmin: isAdmin);
      messenger.showSnackBar(const SnackBar(content: Text('Événement supprimé.')));
      navigator.pop();
    } on EventHasRegistrantsException catch (e) {
      _leaving = false;
      // Quelqu'un s'est inscrit entre-temps.
      if (mounted) await _offerCancelInstead(event, e.message);
    } on EventActionException catch (e) {
      _leaving = false;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _offerCancelInstead(EventModel event, String message) async {
    final cancelInstead = await _confirm(
      title: 'Suppression impossible',
      message: message,
      confirmLabel: "Annuler l'événement",
      cancelLabel: 'Fermer',
    );
    if (cancelInstead && mounted) await _cancelEvent(event);
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    String cancelLabel = 'Annuler',
    bool destructive = false,
  }) async {
    final t = AppTokens.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(cancelLabel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: destructive ? TextButton.styleFrom(foregroundColor: t.danger) : null,
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  // ------------------------------------------------------------ Inscription

  Widget _buildRegisterBar(EventModel event,
      {required String? userId, required bool isRegistered, required DateTime now}) {
    final t = AppTokens.of(context);
    final provider = context.watch<EventProvider>();
    final isGuest = context.watch<AuthProvider>().status != AuthStatus.authenticated;
    final status = event.statusAt(now);
    final remaining = EventRules.remainingSeats(event);
    final seatsText = remaining == null
        ? 'Places illimitées'
        : (remaining == 0 ? 'Aucune place restante' : '$remaining place(s) restante(s)');

    // Raison pour laquelle le bouton est désactivé (null = action possible).
    final blockedReason = isRegistered
        ? EventRules.unregistrationBlocked(event, userId, now)
        : EventRules.registrationBlocked(event, userId, now);

    return Material(
      elevation: 8,
      color: t.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(seatsText,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: t.textSecondary)),
              const SizedBox(height: 8),
              if (isGuest || userId == null)
                Text('Connectez-vous pour vous inscrire à cet événement.',
                    textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium)
              else ...[
                // « Mon billet » : inscrit et événement pas terminé (annulé : billet « Annulé »).
                if (TicketRules.ticketBlockedReason(event, userId, now) == null) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => TicketScreen(event: event))),
                    icon: const Icon(Icons.qr_code_2_rounded),
                    label: const Text('Mon billet'),
                  ),
                  const SizedBox(height: 8),
                ],
                Semantics(
                  button: true,
                  enabled: blockedReason == null,
                  label: blockedReason ?? (isRegistered ? "Annuler l'inscription" : "S'inscrire à l'événement"),
                  child: PillButton(
                    label: blockedReason == null
                        ? (isRegistered ? "Annuler l'inscription" : "S'inscrire à l'événement")
                        : _closedLabel(status, isRegistered),
                    icon: isRegistered ? Icons.close_rounded : Icons.check_circle_outline_rounded,
                    style: isRegistered ? PillStyle.ghost : PillStyle.primary,
                    isLoading: provider.isRegistrationBusy(event.id), // ignore les taps pendant l'envoi
                    onPressed: blockedReason == null ? () => _toggleRegistration(event, userId) : null,
                  ),
                ),
                if (blockedReason != null) ...[
                  const SizedBox(height: 6),
                  Text(blockedReason, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ],
          ),
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
  Future<void> _toggleRegistration(EventModel event, String userId) async {
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<EventProvider>();

    if (!event.isUserRegistered(userId)) {
      final conflict = EventRules.findConflict(event, provider.all, userId, DateTime.now());
      if (conflict != null) {
        final goOn = await _confirm(
          title: "Conflit d'horaire",
          message: "Conflit d'horaire avec « ${conflict.title} ». S'inscrire quand même ?",
          confirmLabel: "S'inscrire",
        );
        if (!goOn) return;
      }
    }

    try {
      final registered = await provider.toggleRegistrationWithResult(event, userId);
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
            if (mounted) _toggleRegistration(event, userId);
          },
        ),
      ));
    }
  }
}

/// En-tête : affiche (avec un dégradé sombre pour la lisibilité) ou dégradé
/// de la couleur de catégorie avec son icône ; catégorie et badges en bas.
class _Header extends StatelessWidget {
  final EventModel event;
  final DateTime now;
  final bool isRegistered;
  const _Header({required this.event, required this.now, required this.isRegistered});

  @override
  Widget build(BuildContext context) {
    final color = EventStyle.categoryColor(event.category);
    // Dégradé net à deux tons de la couleur de catégorie (plus de transparence
    // « boueuse »), icône centrée dans la zone VISIBLE : sous la barre d'app
    // (barre d'état + barre d'outils) et au-dessus du libellé du bas.
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, 0.28)!],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(top: topInset, bottom: 64),
        child: Center(
          child: Icon(EventStyle.categoryIcon(event.category),
              size: 72, color: Colors.white.withValues(alpha: 0.5)),
        ),
      ),
    );
    final badges = EventStyle.badges(event, now, isRegistered: isRegistered);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (event.posterUrl == null)
            fallback
          else
            // Hors-ligne ou lien cassé : le dégradé de la catégorie, jamais d'erreur.
            Semantics(
              image: true,
              label: "Affiche de l'événement ${event.title}",
              child: CachedNetworkImage(
                imageUrl: event.posterUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => fallback,
                errorWidget: (_, __, ___) => fallback,
              ),
            ),
          // Voile sombre SEULEMENT sur une affiche : texte et icônes blancs
          // lisibles sur n'importe quelle photo.
          if (event.posterUrl != null)
            const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x66000000), Color(0x00000000), Color(0x99000000)],
                stops: [0, 0.45, 1],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(event.category.toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                if (badges.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 4, children: badges),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Rangée d'actions rapides : Calendrier et Partager (sauf événement
/// annulé), Itinéraire (si le lieu est localisé).
class _QuickActions extends StatelessWidget {
  final VoidCallback onCalendar;
  final String? calendarBlockedReason; // non null = calendrier désactivé
  final VoidCallback onItinerary;
  final String? itineraryBlockedReason; // non null = itinéraire désactivé
  final VoidCallback onShare;
  final String? shareBlockedReason; // non null = partage désactivé
  const _QuickActions({
    required this.onCalendar,
    required this.calendarBlockedReason,
    required this.onItinerary,
    required this.itineraryBlockedReason,
    required this.onShare,
    required this.shareBlockedReason,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickAction(
            icon: Icons.event_available_outlined,
            label: 'Calendrier',
            semanticLabel: 'Ajouter à mon calendrier',
            onTap: calendarBlockedReason == null ? onCalendar : null,
            disabledMessage: calendarBlockedReason ?? 'Bientôt',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickAction(
            icon: Icons.share_outlined,
            label: 'Partager',
            semanticLabel: "Partager l'événement",
            onTap: shareBlockedReason == null ? onShare : null,
            disabledMessage: shareBlockedReason ?? 'Bientôt',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickAction(
            icon: Icons.directions_outlined,
            label: 'Itinéraire',
            semanticLabel: "Itinéraire jusqu'au lieu",
            onTap: itineraryBlockedReason == null ? onItinerary : null,
            disabledMessage: itineraryBlockedReason ?? 'Bientôt',
          ),
        ),
      ],
    );
  }
}

/// Action rapide (au moins 44 px). Désactivée (onTap null) : grisée, et un
/// toucher ou un appui long explique pourquoi ([disabledMessage]).
class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? semanticLabel;
  final VoidCallback? onTap;
  final String disabledMessage;
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.semanticLabel,
    this.disabledMessage = 'Bientôt',
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final enabled = onTap != null;
    final fg = enabled ? t.primary : t.textSecondary.withValues(alpha: 0.6);
    final button = Semantics(
      button: true,
      enabled: enabled,
      label: enabled ? (semanticLabel ?? label) : '$label, indisponible : $disabledMessage',
      excludeSemantics: true,
      child: Material(
        color: enabled ? t.primary.withValues(alpha: 0.08) : t.outline.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap ??
              () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(disabledMessage))),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: fg, size: 22),
                const SizedBox(height: 4),
                // Libellé réduit si besoin (tiers d'écran étroit, grand texte).
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label,
                        maxLines: 1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return enabled ? button : Tooltip(message: disabledMessage, child: button);
  }
}

/// Petite puce météo (Open-Meteo) pour l'heure de début : température,
/// icône et libellé. Affichée seulement si le lieu est localisé et que
/// l'événement commence dans les 14 jours ; en cas d'échec ou hors-ligne,
/// elle reste simplement cachée (jamais de message d'erreur).
class _WeatherChip extends StatefulWidget {
  final EventModel event;
  final bool isOnline;
  const _WeatherChip({required this.event, required this.isOnline});

  @override
  State<_WeatherChip> createState() => _WeatherChipState();
}

class _WeatherChipState extends State<_WeatherChip> {
  WeatherResult? _weather;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_WeatherChip old) {
    super.didUpdateWidget(old);
    // La fiche se reconstruit souvent (données en direct) : on ne recharge
    // que si la date, le lieu ou la connexion ont changé.
    final e = widget.event, o = old.event;
    if (e.startDate != o.startDate || e.latitude != o.latitude || e.longitude != o.longitude ||
        widget.isOnline != old.isOnline) {
      _load();
    }
  }

  Future<void> _load() async {
    final e = widget.event;
    if (!widget.isOnline || !WeatherRules.shouldShowWeather(e, DateTime.now())) {
      if (_weather != null) setState(() => _weather = null);
      return;
    }
    final response = await OpenMeteoService.instance.forecastAt(e.latitude!, e.longitude!, e.startDate);
    if (!mounted) return;
    setState(() {
      _weather = switch (response) {
        WeatherSuccess(:final weather) => weather,
        WeatherFailure() => null, // échec : la puce reste cachée
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = _weather;
    if (w == null) return const SizedBox.shrink();
    final info = WeatherRules.describe(w.weatherCode);
    final temperature = WeatherRules.formatTemperature(w.temperatureC);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          label: 'Météo prévue au début : $temperature, ${info.label}',
          excludeSemantics: true,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFDBEAFE),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(info.icon, size: 18, color: const Color(0xFF1E40AF)),
                const SizedBox(width: 6),
                // Peut rétrécir (« … ») sur un écran étroit ou en grand texte.
                Flexible(
                  child: Text('$temperature · ${info.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E40AF))),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Carte d'information : icône dans une pastille, titre en gras, sous-titre.
class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  const _InfoCard({required this.icon, required this.color, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.outline),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Jauge des places : « 12 / 50 inscrits », couleur d'alerte à 80 %,
/// « Complet » quand c'est plein. Sans capacité : seulement le nombre.
class _CapacityCard extends StatelessWidget {
  final EventModel event;
  const _CapacityCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final n = event.registeredUserIds.length;
    final ratio = EventRules.capacityRatio(event);
    final Color barColor = event.isFull
        ? t.danger
        : (EventRules.isAlmostFull(event) ? t.warning : t.success);
    // « Places illimitées » n'est affiché qu'une fois : dans la barre du bas.
    final label = ratio == null ? '$n inscrit(s)' : '$n / ${event.capacity} inscrits';

    return Semantics(
      label: ratio == null
          ? '$n inscrits'
          : '$n inscrits sur ${event.capacity}${event.isFull ? ', complet' : ''}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.outline),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.people_alt_outlined, size: 20, color: t.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600))),
                if (event.isFull)
                  Text('Complet',
                      style: TextStyle(color: t.danger, fontWeight: FontWeight.w700, fontSize: 13)),
              ],
            ),
            if (ratio != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 8,
                  color: barColor,
                  backgroundColor: t.outline,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Petite note quand les données viennent du cache (pas de réseau).
class _OfflineNote extends StatelessWidget {
  const _OfflineNote();

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, size: 14, color: t.warning),
          const SizedBox(width: 6),
          // Passe à la ligne au lieu de déborder (écran étroit, grand texte).
          const Flexible(
            child: Text('Hors ligne : dernières données connues',
                style: TextStyle(fontSize: 12, color: Color(0xFF9A3412))),
          ),
        ],
      ),
    );
  }
}

/// Bandeau « Modifié le… » (règle 5) pour prévenir les inscrits.
class _ModifiedBanner extends StatelessWidget {
  final DateTime updatedAt;
  const _ModifiedBanner({required this.updatedAt});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFDBEAFE),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF1E40AF)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Modifié le ${DateFormat("d MMMM 'à' HH:mm", 'fr_FR').format(updatedAt)} : vérifiez la date, le lieu et le prix.',
              style: const TextStyle(color: Color(0xFF1E40AF), fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bandeau rouge d'un événement annulé, avec le motif.
class _CancelledBanner extends StatelessWidget {
  final EventModel event;
  const _CancelledBanner({required this.event});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final when = event.cancelledAt == null
        ? ''
        : ' le ${DateFormat('d MMMM à HH:mm', 'fr_FR').format(event.cancelledAt!)}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        border: Border.all(color: t.danger),
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
    final t = AppTokens.of(context);
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
            errorMaxLines: 2,
          ),
          validator: EventValidators.cancelReason,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Retour')),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: t.danger),
          onPressed: () {
            if (_formKey.currentState!.validate()) Navigator.pop(context, _reasonCtrl.text);
          },
          child: const Text("Annuler l'événement"),
        ),
      ],
    );
  }
}
