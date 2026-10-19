import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/event_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/event_provider.dart';
import 'event_detail_screen.dart';
import 'event_rules.dart';
import 'event_style.dart';

/// Vue mois des événements : grille de 7 colonnes (lundi en premier), un
/// point sous les jours qui ont des événements, flèches mois précédent /
/// suivant. Respecte le filtre et la catégorie actifs de la liste ; toucher
/// un jour le sélectionne (aussi pour la liste) et affiche ses événements.
class EventCalendarScreen extends StatefulWidget {
  const EventCalendarScreen({super.key});

  @override
  State<EventCalendarScreen> createState() => _EventCalendarScreenState();
}

class _EventCalendarScreenState extends State<EventCalendarScreen> {
  late DateTime _month; // 1er jour du mois affiché

  @override
  void initState() {
    super.initState();
    final start = context.read<EventProvider>().selectedDay ?? DateTime.now();
    _month = DateTime(start.year, start.month);
  }

  void _changeMonth(int delta) => setState(() => _month = DateTime(_month.year, _month.month + delta));

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
    final eventDays = EventRules.eventDays(provider.calendarEvents(userId));
    final selected = provider.selectedDay == null ? null : EventRules.dateOnly(provider.selectedDay!);
    final today = EventRules.dateOnly(DateTime.now());
    final cells = EventRules.monthGrid(_month);
    final dayEvents = selected == null ? <EventModel>[] : provider.visibleEvents(userId);

    return Scaffold(
      appBar: AppBar(title: const Text('Calendrier')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // Mois + flèches
            Row(
              children: [
                IconButton(
                  tooltip: 'Mois précédent',
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: () => _changeMonth(-1),
                ),
                Expanded(
                  child: Text(
                    _capitalize(DateFormat.yMMMM('fr_FR').format(_month)),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Mois suivant',
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: () => _changeMonth(1),
                ),
              ],
            ),
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
            // Jours de la semaine
            Row(
              children: [
                for (final label in _weekdayLabels)
                  Expanded(
                    child: Text(label.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // Grille du mois
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cells.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemBuilder: (context, i) {
                final day = cells[i];
                if (day == null) return const SizedBox.shrink();
                return _DayCell(
                  day: day,
                  isSelected: day == selected,
                  isToday: day == today,
                  hasEvents: eventDays.contains(day),
                  onTap: () => provider.setSelectedDay(day == selected ? null : day),
                );
              },
            ),
            const SizedBox(height: 16),
            if (selected == null)
              Text('Touchez un jour pour voir ses événements.',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium)
            else ...[
              Text(_capitalize(DateFormat('EEEE d MMMM', 'fr_FR').format(selected)),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              if (dayEvents.isEmpty)
                Text('Aucun événement ce jour', style: Theme.of(context).textTheme.bodyMedium)
              else
                for (final e in dayEvents)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(width: 5, height: 36, color: EventStyle.categoryColor(e.category)),
                    title: Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${DateFormat('HH:mm', 'fr_FR').format(e.startDate)} · ${e.location}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => EventDetailScreen(event: e))),
                  ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Case d'un jour : numéro, point si des événements, sélection et aujourd'hui.
class _DayCell extends StatelessWidget {
  final DateTime day;
  final bool isSelected;
  final bool isToday;
  final bool hasEvents;
  final VoidCallback onTap;
  const _DayCell({
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.hasEvents,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final label = DateFormat('EEEE d MMMM', 'fr_FR').format(day);
    return Semantics(
      button: true,
      selected: isSelected,
      label: hasEvents ? '$label, avec événements' : label,
      child: Material(
        color: isSelected ? AppColors.primary : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isToday && !isSelected ? const BorderSide(color: AppColors.primary) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${day.day}',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : AppColors.textPrimary)),
              const SizedBox(height: 3),
              _Dot(visible: hasEvents, color: isSelected ? Colors.white : AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Point sous un jour qui a des événements (garde sa place même invisible).
class _Dot extends StatelessWidget {
  final bool visible;
  final Color color;
  const _Dot({required this.visible, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(color: visible ? color : Colors.transparent, shape: BoxShape.circle),
      );
}
