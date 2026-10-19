import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../models/event_model.dart';
import 'event_detail_screen.dart';
import 'event_style.dart';

/// Carte d'événement façon maquette, partagée par la liste et le calendrier :
/// barre de couleur de la catégorie, catégorie en petites capitales, ligne
/// horaire, badges, places et vignette de l'affiche si elle existe.
class EventCard extends StatelessWidget {
  final EventModel event;
  final DateTime now;
  final bool isRegistered;
  const EventCard({super.key, required this.event, required this.now, required this.isRegistered});

  static const double radius = 16;

  @override
  Widget build(BuildContext context) {
    final color = EventStyle.categoryColor(event.category);
    final when = '${DateFormat('d MMM', 'fr_FR').format(event.startDate)} · '
        '${DateFormat('HH:mm', 'fr_FR').format(event.startDate)} · ${event.location}';
    final seats = event.capacity == null
        ? '${event.registeredUserIds.length}'
        : '${event.registeredUserIds.length}/${event.capacity}';
    final badges = EventStyle.badges(event, now, isRegistered: isRegistered);

    return Semantics(
      button: true,
      label: '${event.category}, ${event.title}, $when',
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => EventDetailScreen(event: event)),
          ),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(radius),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 5, color: color),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          if (event.posterUrl != null) ...[
                            _PosterThumbnail(url: event.posterUrl!),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(event.category.toUpperCase(),
                                    style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.1,
                                        color: color)),
                                const SizedBox(height: 4),
                                Text(event.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontSize: 15.5, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 6),
                                Row(children: [
                                  const Icon(Icons.schedule_rounded, size: 14, color: AppColors.textSecondary),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(when,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context).textTheme.bodyMedium),
                                  ),
                                ]),
                                if (badges.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(spacing: 6, runSpacing: 4, children: badges),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.people_alt_outlined, size: 16, color: AppColors.primary),
                              const SizedBox(height: 2),
                              Text(seats,
                                  style: const TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Vignette de l'affiche (mise en cache) ; une icône si l'image ne charge pas.
class _PosterThumbnail extends StatelessWidget {
  final String url;
  const _PosterThumbnail({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: CachedNetworkImage(
        imageUrl: url,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(width: 56, height: 56, color: AppColors.border),
        errorWidget: (_, __, ___) => Container(
          width: 56,
          height: 56,
          color: AppColors.border,
          child: const Icon(Icons.image_not_supported_outlined, size: 20, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

/// Chip de filtre : cible tactile d'au moins 44 px de haut (accessibilité),
/// annoncée comme bouton sélectionné ou non aux lecteurs d'écran.
class EventChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;
  const EventChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: 'Filtre $label',
      excludeSemantics: true,
      child: Material(
        color: selected ? color : Colors.white,
        shape: StadiumBorder(side: BorderSide(color: selected ? color : AppColors.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!selected) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(label,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : AppColors.textPrimary)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
