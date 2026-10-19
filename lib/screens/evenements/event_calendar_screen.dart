import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/event_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/event_provider.dart';
import 'event_card.dart';
import 'event_rules.dart';
import 'event_style.dart';

/// Vue mois des événements : grille de 7 colonnes (lundi en premier), des
/// points de la couleur des catégories sous les jours qui ont des
/// événements, flèches et balayage horizontal pour changer de mois, bouton
/// « Aujourd'hui ». Respecte l'onglet et la catégorie actifs de la liste ;
/// toucher un jour le sélectionne (aussi pour la liste) et affiche ses événements.
class EventCalendarScreen extends StatefulWidget {
  const EventCalendarScreen({super.key});

  @override
  State<EventCalendarScreen> createState() => _EventCalendarScreenState();
}

class _EventCalendarScreenState extends State<EventCalendarScreen> {
  late DateTime _month; // 1er jour du mois affiché

  /// Au-delà de cette vitesse (pixels/s), un glissé horizontal change de mois.
  static const double _swipeVelocity = 250;

  @override
  void initState() {
    super.initState();
    final start = context.read<EventProvider>().selectedDay ?? DateTime.now();
    _month = DateTime(start.year, start.month);
  }

  void _changeMonth(int delta) => setState(() => _month = DateTime(_month.year, _month.month + delta));

  void _goToToday() {
    final today = EventRules.dateOnly(DateTime.now());
    setState(() => _month = DateTime(today.year, today.month));
    context.read<EventProvider>().setSelectedDay(today);
  }

  /// Glisser vers la gauche = mois suivant ; vers la droite = mois précédent.
  void _onSwipe(DragEndDetails details) {
    final v = details.primaryVelocity ?? 0;
    if (v < -_swipeVelocity) _changeMonth(1);
    if (v > _swipeVelocity) _changeMonth(-1);
  }

  /// En-têtes « lun. mar. … dim. » en français : on formate une semaine qui
  /// commence un lundi (1er janvier 2024 était un lundi).
  static final List<String> _weekdayLabels = [
    for (var i = 0; i < 7; i++) DateFormat.E('fr_FR').format(DateTime(2024, 1, 1 + i)),
  ];

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EventProvider>();
    final userId = context.watch<AuthProvider>().currentUser?.id;
    final categoriesByDay = EventRules.categoriesByDay(provider.calendarEvents(userId));
    final selected = provider.selectedDay == null ? null : EventRules.dateOnly(provider.selectedDay!);
    final now = DateTime.now();
    final today = EventRules.dateOnly(now);
    final cells = EventRules.monthGrid(_month);
    final dayEvents = selected == null ? const <EventModel>[] : provider.visibleEvents(userId);
    final isCurrentMonth = _month.year == today.year && _month.month == today.month;

    return Scaffold(
      appBar: AppBar(title: const Text('Calendrier')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // Le balayage horizontal change de mois (en plus des flèches).
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: _onSwipe,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildMonthHeader(isCurrentMonth),
                  if (provider.categoryFilter != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('Catégorie : ${provider.categoryFilter}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: EventStyle.categoryColor(provider.categoryFilter!))),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      for (final label in _weekdayLabels)
                        Expanded(
                          child: Text(label.toUpperCase(),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: cells.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                      mainAxisExtent: 52, // au moins 44 px de haut, même sur un petit écran
                    ),
                    itemBuilder: (context, i) {
                      final day = cells[i];
                      if (day == null) return const SizedBox.shrink();
                      return _DayCell(
                        day: day,
                        isSelected: day == selected,
                        isToday: day == today,
                        categories: categoriesByDay[day] ?? const [],
                        onTap: () => provider.setSelectedDay(day == selected ? null : day),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (selected == null)
              Text('Touchez un jour pour voir ses événements.',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium)
            else ...[
              Text(_capitalize(DateFormat('EEEE d MMMM', 'fr_FR').format(selected)),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              if (dayEvents.isEmpty)
                const _NoEventsThatDay()
              else
                for (final e in dayEvents) ...[
                  EventCard(event: e, now: now, isRegistered: userId != null && e.isUserRegistered(userId)),
                  const SizedBox(height: 12),
                ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMonthHeader(bool isCurrentMonth) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Mois précédent',
          icon: const Icon(Icons.chevron_left_rounded),
          onPressed: () => _changeMonth(-1),
        ),
        // Entre trois boutons : le mois est réduit si la place manque
        // (« Septembre 2026 » en grand texte sur un écran étroit).
        Expanded(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _capitalize(DateFormat.yMMMM('fr_FR').format(_month)),
              maxLines: 1,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Mois suivant',
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: () => _changeMonth(1),
        ),
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
          // Déjà sur le mois courant : on sélectionne quand même aujourd'hui.
          onPressed: _goToToday,
          child: Text("Aujourd'hui",
              style: TextStyle(fontWeight: isCurrentMonth ? FontWeight.w500 : FontWeight.w700)),
        ),
      ],
    );
  }
}

/// Case d'un jour : numéro, jusqu'à 3 points (couleur des catégories),
/// sélection et aujourd'hui.
class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool isSelected;
  final bool isToday;
  final List<String> categories;
  final VoidCallback onTap;
  const _DayCell({
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.categories,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = DateFormat('EEEE d MMMM', 'fr_FR').format(day);
    final semantics = categories.isEmpty ? label : '$label, événements : ${categories.join(', ')}';
    return Semantics(
      button: true,
      selected: isSelected,
      label: semantics,
      excludeSemantics: true,
      child: Material(
        color: isSelected ? AppColors.primary : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isToday && !isSelected ? const BorderSide(color: AppColors.primary) : BorderSide.none,
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${day.day}',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : AppColors.textPrimary)),
              const SizedBox(height: 4),
              // Garde la même hauteur avec ou sans points.
              SizedBox(
                height: 6,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final c in categories.take(3))
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: EventStyle.categoryColor(c),
                          // Contour blanc pour rester visible sur la case sélectionnée.
                          border: isSelected ? Border.all(color: Colors.white, width: 1) : null,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Jour sans événement : petite icône et une ligne.
class _NoEventsThatDay extends StatelessWidget {
  const _NoEventsThatDay();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
            child: const Icon(Icons.event_available_outlined, size: 22, color: AppColors.primary),
          ),
          const SizedBox(height: 10),
          Text('Aucun événement ce jour', style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
    );
  }
}
