import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../models/event_model.dart';
import '../../providers/event_provider.dart';
import 'event_style.dart';
import 'itinerary_rules.dart';
import 'location_service.dart';
import 'osrm_service.dart';

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
        child: Semantics(
          label: "Lieu de l'événement : ${e.location}",
          child: Icon(Icons.location_on, size: 44, color: EventStyle.categoryColor(e.category)),
        ),
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

/// Étapes du calcul d'itinéraire affichées dans le panneau du bas.
enum _RouteStep { locating, routing, done, failed }

/// Carte plein écran : zoom et déplacement, boutons + / − et recentrage.
/// Avec [showItinerary] : position de l'utilisateur, trajet OSRM dessiné,
/// panneau distance / durée et bouton « Ouvrir dans Google Maps ».
class EventMapScreen extends StatefulWidget {
  final EventModel event;
  final bool showItinerary;
  const EventMapScreen({super.key, required this.event, this.showItinerary = false});

  @override
  State<EventMapScreen> createState() => _EventMapScreenState();
}

class _EventMapScreenState extends State<EventMapScreen> {
  final _controller = MapController();
  static const double _initialZoom = 16;
  bool _mapReady = false;

  _RouteStep _step = _RouteStep.locating;
  LatLng? _me;
  RouteResult? _route;
  String? _error;
  PositionError? _positionError;

  LatLng get _destination => EventMap.pointOf(widget.event);

  @override
  void initState() {
    super.initState();
    if (widget.showItinerary) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _computeRoute());
    }
  }

  void _zoomBy(double delta) {
    final camera = _controller.camera;
    _controller.move(camera.center, (camera.zoom + delta).clamp(3.0, 19.0));
  }

  /// Position → trajet OSRM → affichage. Chaque échec reste dans le panneau
  /// (avec « Réessayer ») ; le bouton Google Maps marche dans tous les cas.
  Future<void> _computeRoute() async {
    if (!context.read<EventProvider>().isOnline) {
      setState(() {
        _step = _RouteStep.failed;
        _error = 'Itinéraire indisponible hors ligne';
        _positionError = null;
      });
      return;
    }
    setState(() {
      _step = _RouteStep.locating;
      _error = null;
      _positionError = null;
    });

    final position = await LocationService.currentPosition();
    if (!mounted) return;
    switch (position) {
      case PositionFailure(:final error, :final message):
        setState(() {
          _step = _RouteStep.failed;
          _error = message;
          _positionError = error;
        });
        return;
      case PositionSuccess(:final position):
        setState(() {
          _me = position;
          _step = _RouteStep.routing;
        });
    }

    final response = await OsrmService.instance.route(_me!, _destination);
    if (!mounted) return;
    switch (response) {
      case RouteFailure(:final message):
        setState(() {
          _step = _RouteStep.failed;
          _error = message;
        });
      case RouteSuccess(:final route):
        setState(() {
          _route = route;
          _step = _RouteStep.done;
        });
    }
    _fitCamera();
  }

  /// Cadre la carte pour voir le trajet (ou au moins « moi » et le lieu).
  void _fitCamera() {
    if (!_mapReady || _me == null) return;
    final points = [..._route?.points ?? const <LatLng>[], _me!, _destination];
    _controller.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(points),
      padding: const EdgeInsets.fromLTRB(48, 48, 96, 48), // place pour les boutons à droite
      maxZoom: 17,
    ));
  }

  Future<void> _openGoogleMaps() async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = ItineraryRules.googleMapsDirections(_destination.latitude, _destination.longitude);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) messenger.showSnackBar(const SnackBar(content: Text("Impossible d'ouvrir Google Maps.")));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text("Impossible d'ouvrir Google Maps.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final color = EventStyle.categoryColor(e.category);
    return Scaffold(
      appBar: AppBar(
        // Bouton retour standard (48 px) avec une étiquette claire.
        leading: IconButton(
          tooltip: 'Retour au détail',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.showItinerary ? 'Itinéraire' : e.location, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _controller,
                  options: MapOptions(
                    initialCenter: _destination,
                    initialZoom: _initialZoom,
                    minZoom: 3,
                    maxZoom: 19,
                    onMapReady: () {
                      _mapReady = true;
                      _fitCamera();
                    },
                  ),
                  children: [
                    TileLayer(urlTemplate: EventMap.tileUrl, userAgentPackageName: EventMap.userAgentPackageName),
                    if (_route != null)
                      PolylineLayer(polylines: [
                        Polyline(
                          points: _route!.points,
                          strokeWidth: 5,
                          color: color,
                          borderStrokeWidth: 2,
                          borderColor: Colors.white,
                        ),
                      ]),
                    MarkerLayer(markers: [
                      EventMap.marker(e),
                      if (_me != null) _userMarker(_me!),
                    ]),
                    EventMap.attribution(),
                  ],
                ),
                Positioned(
                  right: 12,
                  top: 12,
                  child: Column(
                    children: [
                      _MapButton(icon: Icons.add, tooltip: 'Zoomer', onPressed: () => _zoomBy(1)),
                      const SizedBox(height: 8),
                      _MapButton(icon: Icons.remove, tooltip: 'Dézoomer', onPressed: () => _zoomBy(-1)),
                      const SizedBox(height: 8),
                      _MapButton(
                        icon: Icons.center_focus_strong_outlined,
                        tooltip: 'Recentrer sur le lieu',
                        onPressed: () => _controller.move(_destination, _initialZoom),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (widget.showItinerary) _buildPanel(),
        ],
      ),
    );
  }

  Marker _userMarker(LatLng point) => Marker(
        point: point,
        width: 44,
        height: 44,
        child: Semantics(
          label: 'Votre position',
          child: Center(
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 6)],
              ),
            ),
          ),
        ),
      );

  /// Panneau du bas : chargement, résultat ou erreur, et Google Maps.
  Widget _buildPanel() {
    final Widget content;
    switch (_step) {
      case _RouteStep.locating:
      case _RouteStep.routing:
        content = Row(children: [
          const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(_step == _RouteStep.locating ? 'Recherche de votre position…' : "Calcul de l'itinéraire…"),
          ),
        ]);
      case _RouteStep.done:
        final r = _route!;
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ItineraryRules.drivingSummary(r.distanceMeters, r.durationSeconds),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(ItineraryRules.walkingSummary(r.distanceMeters), style: Theme.of(context).textTheme.bodyMedium),
          ],
        );
      case _RouteStep.failed:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(_error ?? 'Itinéraire indisponible.')),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 8, children: [
              if (_positionError == PositionError.deniedForever)
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  onPressed: LocationService.openAppSettings,
                  child: const Text('Ouvrir les réglages'),
                ),
              if (_positionError == PositionError.serviceOff)
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  onPressed: LocationService.openLocationSettings,
                  child: const Text('Activer la localisation'),
                ),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                onPressed: _computeRoute,
                child: const Text('Réessayer'),
              ),
            ]),
          ],
        );
    }

    return Material(
      elevation: 8,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Semantics(
            container: true,
            liveRegion: true, // les lecteurs d'écran annoncent le résultat ou l'erreur
            label: 'Itinéraire vers ${widget.event.location}',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                content,
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _openGoogleMaps,
                  icon: const Icon(Icons.directions_outlined),
                  label: const Text('Ouvrir dans Google Maps'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bouton rond de la carte (48 px).
class _MapButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const _MapButton({required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: AppColors.primary),
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        onPressed: onPressed,
      ),
    );
  }
}
