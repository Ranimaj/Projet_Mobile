import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme/app_colors.dart';
import '../../models/event_model.dart';
import 'event_style.dart';

/// Carte OpenStreetMap (gratuite, sans clé) du lieu d'un événement.
///
/// Conditions d'usage des tuiles OSM : identifier l'app
/// ([userAgentPackageName]) et afficher « © OpenStreetMap contributors ».
class EventMap {
  EventMap._();

  static const String tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const String userAgentPackageName = 'com.esprit.campusconnect';

  static LatLng pointOf(EventModel e) => LatLng(e.latitude!, e.longitude!);

  static Marker marker(EventModel e) => Marker(
        point: pointOf(e),
        width: 44,
        height: 44,
        alignment: Alignment.topCenter, // la pointe de l'épingle sur le lieu
        child: Icon(Icons.location_on, size: 44, color: EventStyle.categoryColor(e.category)),
      );

  /// Attribution obligatoire, toujours visible.
  static Widget attribution() => const SimpleAttributionWidget(source: Text('OpenStreetMap contributors'));
}

/// Petite carte non interactive sous le lieu ; un toucher ouvre la carte
/// plein écran. Si les tuiles ne chargent pas (hors-ligne), une carte de
/// remplacement avec le nom du lieu s'affiche à la place.
class EventMapCard extends StatefulWidget {
  final EventModel event;
  final bool isOnline;
  const EventMapCard({super.key, required this.event, required this.isOnline});

  @override
  State<EventMapCard> createState() => _EventMapCardState();
}

class _EventMapCardState extends State<EventMapCard> {
  bool _tilesFailed = false;

  void _onTileError(TileImage tile, Object error, StackTrace? stackTrace) {
    if (_tilesFailed || !mounted) return;
    // Appelé pendant le chargement : on change l'affichage après l'image en cours.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _tilesFailed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    if (!widget.isOnline || _tilesFailed) return _MapPlaceholder(location: e.location);

    return Semantics(
      button: true,
      label: 'Carte du lieu : ${e.location}. Touchez pour agrandir.',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 170,
          child: Stack(
            children: [
              FlutterMap(
                options: MapOptions(
                  initialCenter: EventMap.pointOf(e),
                  initialZoom: 15,
                  // Carte figée dans la fiche : on zoome dans la page plein écran.
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                ),
                children: [
                  TileLayer(
                    urlTemplate: EventMap.tileUrl,
                    userAgentPackageName: EventMap.userAgentPackageName,
                    errorTileCallback: _onTileError,
                  ),
                  MarkerLayer(markers: [EventMap.marker(e)]),
                  EventMap.attribution(),
                ],
              ),
              // Couche transparente qui reçoit le toucher (la carte est figée).
              Positioned.fill(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => EventMapScreen(event: e))),
                  ),
                ),
              ),
              const Positioned(
                top: 8,
                right: 8,
                child: _ExpandHint(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpandHint extends StatelessWidget {
  const _ExpandHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(8)),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.open_in_full_rounded, size: 14, color: AppColors.primary),
          SizedBox(width: 4),
          Text('Agrandir', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.primary)),
        ],
      ),
    );
  }
}

/// Remplace la carte quand elle ne peut pas charger (hors-ligne).
class _MapPlaceholder extends StatelessWidget {
  final String location;
  const _MapPlaceholder({required this.location});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Carte indisponible hors ligne. Lieu : $location',
      excludeSemantics: true,
      child: Container(
        height: 120,
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.border.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.map_outlined, color: AppColors.textSecondary),
            const SizedBox(height: 6),
            Text(location,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('Carte indisponible hors ligne', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Carte plein écran : zoom et déplacement, boutons + / − et recentrage.
class EventMapScreen extends StatefulWidget {
  final EventModel event;
  const EventMapScreen({super.key, required this.event});

  @override
  State<EventMapScreen> createState() => _EventMapScreenState();
}

class _EventMapScreenState extends State<EventMapScreen> {
  final _controller = MapController();
  static const double _initialZoom = 16;

  void _zoomBy(double delta) {
    final camera = _controller.camera;
    _controller.move(camera.center, (camera.zoom + delta).clamp(3.0, 19.0));
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    return Scaffold(
      appBar: AppBar(
        // Bouton retour standard (48 px) avec une étiquette claire.
        leading: IconButton(
          tooltip: 'Retour au détail',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(e.location, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: FlutterMap(
        mapController: _controller,
        options: MapOptions(initialCenter: EventMap.pointOf(e), initialZoom: _initialZoom, minZoom: 3, maxZoom: 19),
        children: [
          TileLayer(urlTemplate: EventMap.tileUrl, userAgentPackageName: EventMap.userAgentPackageName),
          MarkerLayer(markers: [EventMap.marker(e)]),
          EventMap.attribution(),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'zoomIn',
            tooltip: 'Zoomer',
            onPressed: () => _zoomBy(1),
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'zoomOut',
            tooltip: 'Dézoomer',
            onPressed: () => _zoomBy(-1),
            child: const Icon(Icons.remove),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'recenter',
            tooltip: 'Recentrer sur le lieu',
            onPressed: () => _controller.move(EventMap.pointOf(e), _initialZoom),
            child: const Icon(Icons.my_location),
          ),
          const SizedBox(height: 24), // laisse l'attribution visible
        ],
      ),
    );
  }
}
