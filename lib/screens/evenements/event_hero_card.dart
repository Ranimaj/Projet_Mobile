import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/event_model.dart';
import 'event_detail_screen.dart';
import 'itinerary_rules.dart';
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

  /// Distance (m) affichée seulement quand le tri « Près de moi » est actif.
  final double? distanceMeters;
  const EventHeroCard({super.key, required this.event, required this.now, this.distanceMeters});

  @override
  Widget build(BuildContext context) {
    final color = EventStyle.categoryColor(event.category);
    final countdown = EventRules.countdown(event.startDate, now);
    final date = DateFormat('EEEE d MMMM · HH:mm', 'fr_FR').format(event.startDate);

    return Semantics(
      button: true,
      label: 'Prochain événement : ${event.title}, $date, ${event.location}, '
          '${EventRules.priceLabel(event)}, $countdown'
          '${distanceMeters == null ? '' : ', à ${ItineraryRules.formatDistance(distanceMeters!)}'}',
      excludeSemantics: true,
      child: Material(
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Fond : l'affiche si elle existe (chargement / erreur / hors-ligne :
            // le dégradé de la catégorie), sinon le dégradé.
            Positioned.fill(child: _background(color)),
            // Voile sombre sur l'affiche : le texte blanc reste lisible.
            if (event.posterUrl != null)
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x99000000), Color(0x66000000), Color(0xB3000000)],
                    ),
                  ),
                ),
              ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => EventDetailScreen(event: event)),
                ),
                child: Padding(
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
                                  color: Colors.white70,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.1),
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
                      if (distanceMeters != null) ...[
                        const SizedBox(height: 4),
                        _HeroLine(icon: Icons.near_me_outlined, text: ItineraryRules.formatDistance(distanceMeters!)),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _background(Color color) {
    final gradient = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: 0.72)],
        ),
      ),
    );
    final url = event.posterUrl;
    if (url == null) return gradient;
    return Semantics(
      image: true,
      label: "Affiche de l'événement ${event.title}",
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, __) => gradient,
        errorWidget: (_, __, ___) => gradient,
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
