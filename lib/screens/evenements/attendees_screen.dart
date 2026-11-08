import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/event_model.dart';
import '../../providers/event_provider.dart';
import 'event_card.dart';
import 'event_rules.dart';
import 'scan_ticket_screen.dart';
import 'ticket_rules.dart';

/// BF8.5 — participants d'un événement (organisateur ou admin) : résumé
/// (inscrits, présents, payés, recette attendue), recherche, filtres, et
/// pointage « Présent » / « Payé » en direct.
///
/// Événement annulé : lecture seule. Terminé : présences en lecture seule,
/// mais « Payé » reste modifiable (paiement noté après coup).
class AttendeesScreen extends StatefulWidget {
  final EventModel event;
  const AttendeesScreen({super.key, required this.event});

  @override
  State<AttendeesScreen> createState() => _AttendeesScreenState();
}

class _AttendeesScreenState extends State<AttendeesScreen> {
  late final Stream<({EventModel? event, bool fromCache})> _live;
  final _searchCtrl = TextEditingController();
  String _query = '';
  AttendeeFilter _filter = AttendeeFilter.all;

  Map<String, String> _names = {};
  bool _namesLoading = false;
  Set<String> _namesFor = {};

  @override
  void initState() {
    super.initState();
    // Même flux en direct que la fiche (events/{id}.snapshots()).
    _live = context.read<EventProvider>().watchEvent(widget.event.id);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Charge les noms quand la liste des inscrits change (une seule fois par
  /// nouvel ensemble d'uids ; le provider garde un cache).
  void _ensureNames(EventModel event) {
    final uids = event.registeredUserIds.toSet();
    if (uids.isEmpty || _namesFor.containsAll(uids)) return;
    _namesFor = uids;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      setState(() => _namesLoading = true);
      final names = await context.read<EventProvider>().attendeeNames(uids.toList());
      if (!mounted) return;
      setState(() {
        _names = names;
        _namesLoading = false;
      });
    });
  }

  Future<void> _toggle(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on EventActionException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Scan d'un billet : connexion requise ; on lit le QR, on vérifie (bon
  /// événement, inscrit, pas déjà pointé, pointage permis), puis on POINTE
  /// présent (jamais l'inverse) et on affiche le résultat.
  Future<void> _scan(EventModel event) async {
    final provider = context.read<EventProvider>();
    final messenger = ScaffoldMessenger.of(context);
    if (!provider.isOnline) {
      messenger.showSnackBar(const SnackBar(content: Text('Connexion requise pour scanner les billets.')));
      return;
    }
    final raw = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanTicketScreen()));
    if (raw == null || !mounted) return; // scanner fermé sans lecture

    final latest = provider.findById(event.id) ?? event;
    final result = TicketRules.scanVerdict(latest, raw, DateTime.now());
    final uid = result.uid;
    var name = '';
    if (uid != null) {
      name = _names[uid] ?? (await provider.attendeeNames([uid]))[uid] ?? EventRules.fallbackName(uid);
    }

    late final String title;
    late final String detail;
    var ok = false;
    switch (result.verdict) {
      case ScanVerdict.markPresent:
        try {
          await provider.markPresent(event.id, uid!);
          title = 'Présent : $name';
          detail = 'Le participant est pointé présent.';
          ok = true;
        } on EventActionException catch (e) {
          title = 'Pointage impossible';
          detail = e.message;
        }
      case ScanVerdict.alreadyPresent:
        title = 'Déjà pointé';
        detail = '$name est déjà marqué présent.';
        ok = true;
      case ScanVerdict.invalid:
        title = 'Billet invalide';
        detail = "Ce code n'est pas un billet CampusConnect.";
      case ScanVerdict.otherEvent:
        title = 'Billet invalide';
        detail = 'Ce billet concerne un autre événement.';
      case ScanVerdict.notRegistered:
        title = 'Pas inscrit';
        detail = "$name n'est pas inscrit à cet événement.";
      case ScanVerdict.blocked:
        title = 'Pointage impossible';
        detail = result.reason ?? '';
    }
    if (!mounted) return;
    final again = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _ScanResultSheet(title: title, detail: detail, ok: ok),
    );
    if (again == true && mounted) await _scan(event);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<({EventModel? event, bool fromCache})>(
      stream: _live,
      builder: (context, snapshot) {
        final provider = context.watch<EventProvider>();
        final data = snapshot.data;
        final known = provider.findById(widget.event.id) ?? widget.event;
        final deleted = data != null && data.event == null && !data.fromCache;
        final event = data?.event ?? known;
        final isLoading = snapshot.connectionState == ConnectionState.waiting && data == null;
        final isOffline = snapshot.hasError || (data?.fromCache ?? false);
        if (!deleted) _ensureNames(event);

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Participants'),
                Text(event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w400)),
              ],
            ),
            actions: [
              if (!deleted)
                IconButton(
                  tooltip: 'Scanner un billet',
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  onPressed: () => _scan(event),
                ),
            ],
          ),
          body: deleted
              ? const _Message(icon: Icons.event_busy_outlined, text: "Cet événement n'existe plus.")
              : _buildBody(provider, event, isLoading: isLoading, isOffline: isOffline),
        );
      },
    );
  }

  Widget _buildBody(EventProvider provider, EventModel event, {required bool isLoading, required bool isOffline}) {
    final t = AppTokens.of(context);
    final now = DateTime.now();
    final paidEvent = !EventRules.isFree(event);
    final stats = EventRules.attendeeStats(event);
    final attendees = EventRules.filterAttendees(event, _names, filter: _filter, query: _query);

    final readOnlyNote = event.status == EventStatus.cancelled
        ? 'Événement annulé : liste en lecture seule.'
        : (!now.isBefore(event.endDate)
            ? (paidEvent
                ? 'Événement terminé : présences en lecture seule, paiements encore modifiables.'
                : 'Événement terminé : liste en lecture seule.')
            : null);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        if (isLoading) const LinearProgressIndicator(minHeight: 2),
        if (isOffline) const _Note(icon: Icons.wifi_off_rounded, text: 'Hors ligne : dernières données connues'),
        if (readOnlyNote != null) _Note(icon: Icons.lock_outline_rounded, text: readOnlyNote),
        _SummaryCard(stats: stats, paidEvent: paidEvent),
        const SizedBox(height: 16),
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Rechercher un participant',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Effacer',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() {
                      _searchCtrl.clear();
                      _query = '';
                    }),
                  ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (value, label) in [
              (AttendeeFilter.all, 'Tous'),
              (AttendeeFilter.present, 'Présents'),
              (AttendeeFilter.absent, 'Absents'),
              if (paidEvent) (AttendeeFilter.unpaid, 'Non payés'),
            ])
              EventChip(label: label, selected: _filter == value, onTap: () => setState(() => _filter = value)),
          ],
        ),
        const SizedBox(height: 12),
        if (_namesLoading)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Chargement des noms…', style: TextStyle(fontSize: 12, color: t.textSecondary)),
          ),
        if (attendees.isEmpty)
          _Message(icon: Icons.people_outline_rounded, text: _emptyMessage(event))
        else
          for (final a in attendees)
            _AttendeeRow(
              name: a.name,
              present: event.checkedInUserIds.contains(a.uid),
              paid: event.paidUserIds.contains(a.uid),
              showPaid: paidEvent,
              presentBlocked: EventRules.presentBlockedReason(event, a.uid, now),
              paidBlocked: EventRules.paidBlockedReason(event, a.uid),
              presentBusy: provider.isAttendanceBusy(event.id, 'checkedInUserIds', a.uid),
              paidBusy: provider.isAttendanceBusy(event.id, 'paidUserIds', a.uid),
              onPresent: () => _toggle(() => provider.togglePresent(event.id, a.uid)),
              onPaid: () => _toggle(() => provider.togglePaid(event.id, a.uid)),
            ),
      ],
    );
  }

  String _emptyMessage(EventModel event) {
    if (event.registeredUserIds.isEmpty) return 'Aucun inscrit pour le moment.';
    if (_query.trim().isNotEmpty) return 'Aucun participant ne correspond à « ${_query.trim()} ».';
    switch (_filter) {
      case AttendeeFilter.all:
        return 'Aucun inscrit pour le moment.';
      case AttendeeFilter.present:
        return 'Aucun participant pointé présent.';
      case AttendeeFilter.absent:
        return 'Tout le monde est présent.';
      case AttendeeFilter.unpaid:
        return 'Tous les inscrits ont payé.';
    }
  }
}

/// Résumé : inscrits / capacité avec la jauge, présents, payés, recette.
class _SummaryCard extends StatelessWidget {
  final ({int registered, int? capacity, int present, int paid, double expectedRevenue, double? fillRatio}) stats;
  final bool paidEvent;
  const _SummaryCard({required this.stats, required this.paidEvent});

  static String _money(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final ratio = stats.fillRatio;
    final registeredText =
        stats.capacity == null ? '${stats.registered} inscrit(s)' : '${stats.registered} / ${stats.capacity} inscrits';
    final barColor = ratio == null
        ? t.success
        : (ratio >= 1 ? t.danger : (ratio >= 0.8 ? t.warning : t.success));

    return Semantics(
      container: true,
      label: '$registeredText, ${stats.present} présent(s)'
          '${paidEvent ? ', ${stats.paid} payé(s), recette attendue ${_money(stats.expectedRevenue)} dinars' : ''}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.outline),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(registeredText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (ratio != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                    value: ratio, minHeight: 8, color: barColor, backgroundColor: t.outline),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _Stat(icon: Icons.how_to_reg_outlined, text: '${stats.present} présent(s)'),
                if (paidEvent) _Stat(icon: Icons.payments_outlined, text: '${stats.paid} payé(s)'),
              ],
            ),
            if (paidEvent) ...[
              const SizedBox(height: 8),
              Text('Recette attendue : ${_money(stats.expectedRevenue)} TND',
                  style: TextStyle(fontWeight: FontWeight.w600, color: t.primary)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Stat({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18, color: AppTokens.of(context).textSecondary),
        const SizedBox(width: 6),
        Text(text),
      ]);
}

/// Une ligne : initiale, nom, bascules « Présent » et (si payant) « Payé ».
class _AttendeeRow extends StatelessWidget {
  final String name;
  final bool present;
  final bool paid;
  final bool showPaid;
  final String? presentBlocked;
  final String? paidBlocked;
  final bool presentBusy;
  final bool paidBusy;
  final VoidCallback onPresent;
  final VoidCallback onPaid;
  const _AttendeeRow({
    required this.name,
    required this.present,
    required this.paid,
    required this.showPaid,
    required this.presentBlocked,
    required this.paidBlocked,
    required this.presentBusy,
    required this.paidBusy,
    required this.onPresent,
    required this.onPaid,
  });

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppTokens.of(context).primary.withValues(alpha: 0.12),
            child: Text(initial, style: TextStyle(color: AppTokens.of(context).primary, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          _ToggleChip(
            label: 'Présent',
            icon: Icons.how_to_reg_outlined,
            on: present,
            busy: presentBusy,
            blockedReason: presentBlocked,
            semanticsName: name,
            onTap: onPresent,
          ),
          if (showPaid) ...[
            const SizedBox(width: 6),
            _ToggleChip(
              label: 'Payé',
              icon: Icons.payments_outlined,
              on: paid,
              busy: paidBusy,
              blockedReason: paidBlocked,
              semanticsName: name,
              onTap: onPaid,
            ),
          ],
        ],
      ),
    );
  }
}

/// Bascule de 48 px minimum. Bloquée : grisée, et un toucher explique pourquoi.
class _ToggleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool on;
  final bool busy;
  final String? blockedReason;
  final String semanticsName;
  final VoidCallback onTap;
  const _ToggleChip({
    required this.label,
    required this.icon,
    required this.on,
    required this.busy,
    required this.blockedReason,
    required this.semanticsName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = blockedReason == null;
    final color = on ? AppTokens.of(context).success : AppTokens.of(context).textSecondary;
    return Semantics(
      toggled: on,
      enabled: enabled,
      button: true,
      label: '$label : $semanticsName${enabled ? '' : ', $blockedReason'}',
      excludeSemantics: true,
      child: Material(
        color: on ? AppTokens.of(context).success.withValues(alpha: enabled ? 0.14 : 0.07) : AppTokens.of(context).surface,
        shape: StadiumBorder(
          side: BorderSide(color: on ? AppTokens.of(context).success : AppTokens.of(context).outline),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: busy
              ? null
              : (enabled
                  ? onTap
                  : () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(blockedReason!)))),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (busy)
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    Icon(on ? Icons.check_circle : icon, size: 18, color: enabled ? color : color.withValues(alpha: 0.5)),
                  const SizedBox(width: 4),
                  Text(label,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: enabled ? color : color.withValues(alpha: 0.5))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Résultat d'un scan : icône verte (pointé) ou rouge (refusé), titre,
/// détail, et « Scanner un autre billet ».
class _ScanResultSheet extends StatelessWidget {
  final String title;
  final String detail;
  final bool ok;
  const _ScanResultSheet({required this.title, required this.detail, required this.ok});

  @override
  Widget build(BuildContext context) {
    final color = ok ? AppTokens.of(context).success : AppTokens.of(context).danger;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Semantics(
          liveRegion: true,
          container: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ok ? Icons.check_circle_rounded : Icons.cancel_rounded, size: 56, color: color),
              const SizedBox(height: 10),
              Text(title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(detail, textAlign: TextAlign.center),
              const SizedBox(height: 18),
              OverflowBar(
                alignment: MainAxisAlignment.spaceBetween,
                overflowAlignment: OverflowBarAlignment.center,
                spacing: 8,
                overflowSpacing: 8,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(minimumSize: const Size(44, 48)),
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Fermer'),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(44, 48)),
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: const Text('Scanner un autre billet'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Note({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: AppTokens.of(context).warningSoft, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(icon, size: 16, color: AppTokens.of(context).warning),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, color: AppTokens.of(context).warning))),
      ]),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Message({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(children: [
        Icon(icon, size: 32, color: AppTokens.of(context).textSecondary),
        const SizedBox(height: 10),
        Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
      ]),
    );
  }
}
