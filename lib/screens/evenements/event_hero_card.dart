import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/event_model.dart';
import 'event_detail_screen.dart';
import 'event_rules.dart';
import 'event_style.dart';

/// Carte « Prochain événement » en haut de « À venir » : grande carte dans
/// la couleur de la catégorie, avec un compte à rebours.
///
/// Écrans étroits / grand texte : chaque ligne a une partie qui peut
/// rétrécir (Expanded + une seule ligne + « … ») et une partie à taille
/// naturelle (la pastille du compte à rebours, les icônes).
class EventHeroCard extends StatelessWidget {
  final EventModel event;
  final DateTime now;
  const EventHeroCard({super.key, required this.event, required this.now});

  @override
  Widget build(BuildContext context) {
    final color = EventStyle.categoryColor(event.category);
    final countdown = EventRules.countdown(event.startDate, now);
    final date = DateFormat('EEEE d MMMM · HH:mm', 'fr_FR').format(event.startDate);

    return Semantics(
      button: true,
      label: 'Prochain événement : ${event.title}, $date, ${event.location}, '
          '${EventRules.priceLabel(event)}, $countdown',
      excludeSemantics: true,
      child: Material(
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => EventDetailScreen(event: event)),
          ),
          child: Ink(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color, color.withValues(alpha: 0.72)],
              ),
            ),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Le libellé rétrécit (« … ») ; la pastille garde sa taille.
                    Expanded(
                      child: Text(
                        'PROCHAIN ÉVÉNEMENT · ${event.category.toUpperCase()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(countdown,
                          maxLines: 1,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(event.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                _HeroLine(icon: Icons.calendar_today_outlined, text: date[0].toUpperCase() + date.substring(1)),
                const SizedBox(height: 4),
                _HeroLine(icon: Icons.place_outlined, text: event.location),
                const SizedBox(height: 4),
                _HeroLine(icon: Icons.sell_outlined, text: EventRules.priceLabel(event)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ligne icône + texte : le texte prend la place restante, sur une ligne.
class _HeroLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _HeroLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 15, color: Colors.white70),
      const SizedBox(width: 6),
      Expanded(
        child: Text(text,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13)),
      ),
    ]);
  }
}
