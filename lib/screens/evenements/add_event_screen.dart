import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/event_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/event_provider.dart';
import '../../services/storage_service.dart';
import '../../widgets/app_image.dart';
import '../../widgets/primary_button.dart';
import 'category_classifier.dart';
import 'category_classifier_loader.dart';
import 'event_categories.dart';
import 'event_rules.dart';
import 'event_validators.dart';
import 'photon_service.dart';
import 'poster_compressor.dart';
import 'poster_rules.dart';

/// BF8.3 / BF8.4 — un seul formulaire pour créer OU modifier un événement.
/// Création si [existing] est null, modification sinon.
class AddEventScreen extends StatefulWidget {
  final EventModel? existing;

  /// Chargement du classifieur de catégorie (par défaut : l'asset embarqué).
  /// Remplaçable dans les tests.
  @visibleForTesting
  final Future<CategoryClassifier?> Function()? loadClassifier;

  const AddEventScreen({super.key, this.existing, this.loadClassifier});

  @override
  State<AddEventScreen> createState() => _AddEventScreenState();
}

/// Champs du formulaire, pour savoir lesquels ont été « touchés ».
enum _Field { title, description, location, capacity, price, category, start, end }

class _AddEventScreenState extends State<AddEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _endFieldKey = GlobalKey<FormFieldState<DateTime>>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _capacityCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _titleFocus = FocusNode();
  final _descFocus = FocusNode();
  final _locationFocus = FocusNode();
  final _capacityFocus = FocusNode();
  final _priceFocus = FocusNode();

  /// Affichage des erreurs : un champ montre son erreur seulement s'il a été
  /// modifié PUIS quitté (« touché »), ou après une première tentative
  /// d'envoi. Ensuite l'erreur se met à jour en direct pendant la saisie.
  /// À l'ouverture, aucun champ n'affiche d'erreur.
  final Set<_Field> _edited = {};
  final Set<_Field> _touched = {};
  bool _submitAttempted = false;

  AutovalidateMode _modeFor(_Field field) => (_submitAttempted || _touched.contains(field))
      ? AutovalidateMode.always
      : AutovalidateMode.disabled;

  /// Quand le champ perd le focus après avoir été modifié, il devient « touché ».
  void _watchFocus(FocusNode node, _Field field) {
    node.addListener(() {
      if (!mounted || node.hasFocus || !_edited.contains(field) || _touched.contains(field)) return;
      setState(() => _touched.add(field));
    });
  }

  /// Id généré une seule fois à l'ouverture et réutilisé à chaque nouvel
  /// essai : un réseau lent ne peut jamais créer deux fois l'événement.
  late final String _eventId;
  String? _category;
  String? _initialCategory;
  late DateTime _start;
  late DateTime _end;
  bool _submitting = false;
  bool _saved = false;

  // --- Lieu : suggestions Photon pendant la saisie (BF9.1) ---
  /// Une instance PAR formulaire : au plus 1 requête toutes les 500 ms.
  final _photon = PhotonService();
  Timer? _placeDebounce;

  /// Compteur de requêtes : une réponse qui arrive après une recherche plus
  /// récente est ignorée (on ne peut pas annuler une requête http en cours).
  int _placeRequestId = 0;
  List<PlaceSuggestion> _placeSuggestions = const [];
  bool _placeLoading = false;
  bool _placeNoResult = false;

  /// Coordonnées de la suggestion choisie (null = lieu non localisé) et le
  /// texte exact au moment du choix : si le texte change, elles sont effacées.
  double? _placeLat;
  double? _placeLng;
  String? _placeLabel;
  double _lastKeyboardInset = 0;

  bool get _placeLocated => _placeLat != null && _placeLng != null;

  // --- Suggestion de catégorie (modèle embarqué, aucun réseau) ---
  /// Nombre minimal de caractères (titre + description) avant de proposer.
  static const int _suggestMinChars = 15;
  static const Duration _suggestDelay = Duration(milliseconds: 600);
  final _categoryFieldKey = GlobalKey<FormFieldState<String>>();
  CategoryClassifier? _classifier;
  Timer? _suggestDebounce;
  CategorySuggestion? _suggestion;

  /// Texte (titre + description) déjà analysé ou en attente : un simple
  /// déplacement du curseur ne relance pas le calcul.
  String? _suggestText;

  /// Catégorie proposée que l'utilisateur a ignorée : elle n'est plus
  /// reproposée tant que le texte suggère la même catégorie.
  String? _dismissedSuggestion;

  /// Le choix reste toujours manuel : la puce n'apparaît que si la
  /// suggestion diffère de la catégorie choisie et n'a pas été ignorée.
  bool get _showSuggestion =>
      _suggestion != null &&
      _suggestion!.category != _category &&
      _suggestion!.category != _dismissedSuggestion &&
      !_submitting;

  // --- Affiche (fichier sur le téléphone) ---
  /// JPEG déjà compressé, choisi mais PAS encore enregistré : il est rangé
  /// dans le dossier de l'app à l'enregistrement, pour ne pas laisser
  /// d'images orphelines quand le formulaire est abandonné.
  Uint8List? _posterBytes;

  /// Chemin déjà obtenu pour [_posterBytes] : un nouvel essai d'enregistrement
  /// ne copie pas l'image une seconde fois.
  String? _savedPosterPath;

  /// Modification : l'affiche existante a été retirée.
  bool _posterRemoved = false;
  bool _posterPreparing = false;
  bool _posterUploading = false;

  String? get _existingPosterUrl => widget.existing?.posterUrl;

  /// Affiche actuellement montrée (choisie, ou existante non retirée).
  bool get _hasPoster => _posterBytes != null || (!_posterRemoved && _existingPosterUrl != null);

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _eventId = e?.id ?? const Uuid().v4();
    _watchFocus(_titleFocus, _Field.title);
    _watchFocus(_descFocus, _Field.description);
    _watchFocus(_locationFocus, _Field.location);
    _watchFocus(_capacityFocus, _Field.capacity);
    _watchFocus(_priceFocus, _Field.price);
    // Perte du focus du champ « Lieu » : on ferme la liste de suggestions.
    _locationFocus.addListener(() {
      if (!_locationFocus.hasFocus) _closePlaceList();
    });
    if (e != null) {
      _titleCtrl.text = e.title;
      _descCtrl.text = e.description;
      _locationCtrl.text = e.location;
      // Ancien événement déjà localisé : tant que le texte ne change pas, on
      // garde ses coordonnées.
      if (e.latitude != null && e.longitude != null) {
        _placeLat = e.latitude;
        _placeLng = e.longitude;
        _placeLabel = e.location;
      }
      _capacityCtrl.text = e.capacity?.toString() ?? '';
      _priceCtrl.text = _priceText(e.price);
      // Une ancienne catégorie hors liste oblige à en choisir une valide.
      _category = EventCategories.all.contains(e.category) ? e.category : null;
      _initialCategory = _category;
      _start = e.startDate;
      _end = e.endDate;
    } else {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      _category = EventCategories.all.first;
      _start = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 14, 0);
      _end = _start.add(EventModel.defaultDuration);
    }
    // Ajoutés APRÈS le pré-remplissage : en modification, rien n'est
    // proposé tant que l'utilisateur ne retouche pas le titre ou la description.
    _titleCtrl.addListener(_onSuggestTextChanged);
    _descCtrl.addListener(_onSuggestTextChanged);
    (widget.loadClassifier ?? CategoryClassifierLoader.load)().then((classifier) {
      if (!mounted || classifier == null) return;
      _classifier = classifier;
      // Texte saisi avant la fin du chargement : on le traite maintenant.
      if (_suggestText != null) _scheduleSuggestion();
    }, onError: (Object e) => debugPrint('Suggestion de catégorie indisponible : $e'));
  }

  void _onSuggestTextChanged() {
    final text = '${_titleCtrl.text}\n${_descCtrl.text}';
    if (text == _suggestText) return;
    _suggestText = text;
    _scheduleSuggestion();
  }

  /// Attend 600 ms sans frappe, puis calcule la suggestion. Sous 15
  /// caractères, la puce disparaît tout de suite.
  void _scheduleSuggestion() {
    _suggestDebounce?.cancel();
    final title = _titleCtrl.text.trim();
    final description = _descCtrl.text.trim();
    if (title.length + description.length < _suggestMinChars) {
      if (_suggestion != null) setState(() => _suggestion = null);
      return;
    }
    final classifier = _classifier;
    if (classifier == null) return;
    _suggestDebounce = Timer(_suggestDelay, () {
      if (!mounted) return;
      final next = classifier.suggest(title, description);
      setState(() {
        _suggestion = next;
        // Nouvelle catégorie proposée (ou plus rien) : l'ancien refus ne compte plus.
        if (next?.category != _dismissedSuggestion) _dismissedSuggestion = null;
      });
    });
  }

  void _applySuggestion() {
    final s = _suggestion;
    if (s == null) return;
    _categoryFieldKey.currentState?.didChange(s.category);
    setState(() {
      _category = s.category;
      _touched.add(_Field.category);
    });
  }

  void _dismissSuggestion() {
    final s = _suggestion;
    if (s == null) return;
    setState(() => _dismissedSuggestion = s.category);
  }

  @override
  void dispose() {
    _suggestDebounce?.cancel();
    _placeDebounce?.cancel();
    for (final c in [_titleCtrl, _descCtrl, _locationCtrl, _capacityCtrl, _priceCtrl]) {
      c.dispose();
    }
    for (final f in [_titleFocus, _descFocus, _locationFocus, _capacityFocus, _priceFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  int? get _capacityValue {
    final v = _capacityCtrl.text.trim();
    return v.isEmpty ? null : int.parse(v);
  }

  /// Prix saisi, arrondi à 2 décimales (null = gratuit). Appelé après validation.
  double? get _priceValue => EventValidators.parsePrice(_priceCtrl.text);

  /// Prix existant affiché dans le champ : vide si gratuit, « 15 » ou « 12,50 ».
  static String _priceText(double? price) {
    if (price == null || price == 0) return '';
    return price == price.roundToDouble()
        ? price.toStringAsFixed(0)
        : price.toStringAsFixed(2).replaceAll('.', ',');
  }

  /// Le formulaire contient-il des modifications non enregistrées ?
  bool get _isDirty {
    final e = widget.existing;
    String n(String s) => EventValidators.normalize(s);
    if (e == null) {
      return _posterBytes != null ||
          [_titleCtrl, _descCtrl, _locationCtrl, _capacityCtrl, _priceCtrl].any((c) => n(c.text).isNotEmpty);
    }
    return n(_titleCtrl.text) != e.title ||
        n(_descCtrl.text) != e.description ||
        n(_locationCtrl.text) != e.location ||
        _category != _initialCategory ||
        _start != e.startDate ||
        _end != e.endDate ||
        _capacityCtrl.text.trim() != (e.capacity?.toString() ?? '') ||
        _priceCtrl.text.trim() != _priceText(e.price) ||
        _posterBytes != null ||
        _posterRemoved;
  }

  Future<void> _confirmLeave() async {
    if (!_isDirty) {
      Navigator.pop(context);
      return;
    }
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Abandonner les modifications ?'),
        content: const Text('Les informations saisies seront perdues.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Continuer')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Abandonner')),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.pop(context);
  }

  Future<DateTime?> _pickDateTime(DateTime initial, {required DateTime first, required DateTime last}) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? first : (initial.isAfter(last) ? last : initial),
      firstDate: first,
      lastDate: last,
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  Future<void> _pickStart(FormFieldState<DateTime> field) async {
    final today = DateTime.now();
    final first = DateTime(today.year, today.month, today.day);
    final picked = await _pickDateTime(
      _start,
      first: _start.isBefore(first) ? _start : first,
      last: today.add(const Duration(days: 366)),
    );
    if (picked == null) return;
    // On garde la même durée : la fin se décale avec le début.
    final duration = _end.difference(_start);
    setState(() {
      _start = picked;
      _end = picked.add(duration);
      _touched.add(_Field.start);
    });
    field.didChange(picked);
    _endFieldKey.currentState?.didChange(_end);
  }

  Future<void> _pickEnd(FormFieldState<DateTime> field) async {
    final first = DateTime(_start.year, _start.month, _start.day);
    final picked = await _pickDateTime(_end, first: first, last: first.add(const Duration(days: 4)));
    if (picked == null) return;
    setState(() {
      _end = picked;
      _touched.add(_Field.end);
    });
    field.didChange(picked);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------- Affiche

  /// Galerie → contrôle (type réel, taille) → compression. Rien n'est
  /// enregistré ici. Galerie annulée : rien ne se passe.
  Future<void> _pickPoster() async {
    final messenger = ScaffoldMessenger.of(context);
    XFile? file;
    try {
      // requestFullMetadata: false → pas besoin d'accès complet aux métadonnées.
      file = await ImagePicker().pickImage(source: ImageSource.gallery, requestFullMetadata: false);
    } on PlatformException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.code.toLowerCase().contains('denied')
            ? 'Accès aux photos refusé : autorisez-le dans les réglages du téléphone.'
            : "Impossible d'ouvrir la galerie."),
      ));
      return;
    }
    if (file == null) return; // sélection annulée : en silence

    Uint8List? bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (_) {
      bytes = null;
    }
    final error = PosterRules.validate(file.name, bytes);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    setState(() => _posterPreparing = true);
    Uint8List? compressed;
    try {
      compressed = await PosterCompressor.compress(bytes!);
    } catch (_) {
      compressed = null;
    }
    if (!mounted) return;
    setState(() {
      _posterPreparing = false;
      if (compressed != null) {
        _posterBytes = compressed;
        _savedPosterPath = null; // nouvelle image : pas encore enregistrée
        _posterRemoved = false;
      }
    });
    if (compressed == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Impossible de préparer cette image. Essayez-en une autre.')));
    }
  }

  void _removePoster() => setState(() {
        _posterBytes = null;
        _savedPosterPath = null;
        _posterRemoved = _existingPosterUrl != null;
      });

  /// Enregistre l'affiche choisie (si besoin) sur le téléphone au moment
  /// d'enregistrer l'événement. proceed false = l'organisateur a annulé ;
  /// url null = pas de nouvelle affiche.
  Future<({bool proceed, String? url})> _ensurePosterSaved() async {
    final bytes = _posterBytes;
    if (bytes == null) return (proceed: true, url: null);
    if (_savedPosterPath != null) return (proceed: true, url: _savedPosterPath); // déjà enregistrée

    while (true) {
      setState(() {
        _submitting = true;
        _posterUploading = true;
      });
      String? path;
      try {
        path = await _savePoster(bytes);
      } catch (e) {
        debugPrint("Enregistrement de l'affiche échoué : $e");
      }
      if (!mounted) return (proceed: false, url: null);
      setState(() {
        _submitting = false;
        _posterUploading = false;
      });
      if (path != null) {
        _savedPosterPath = path;
        return (proceed: true, url: path);
      }
      final choice = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text("Affiche non enregistrée"),
          content: const Text("L'affiche n'a pas pu être enregistrée sur le téléphone."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Annuler')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'without'), child: const Text('Enregistrer sans affiche')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'retry'), child: const Text('Réessayer')),
          ],
        ),
      );
      if (!mounted) return (proceed: false, url: null);
      if (choice == 'retry') continue;
      // « Sans affiche » : on enregistre le reste ; la nouvelle image n'est
      // pas utilisée (une affiche existante reste, sauf si elle a été retirée).
      return (proceed: choice == 'without', url: null);
    }
  }

  /// Range le JPEG déjà compressé dans le dossier de l'app (`events/<id>/`)
  /// via [StorageService] ; renvoie son chemin, enregistré dans posterUrl.
  Future<String> _savePoster(Uint8List bytes) async {
    final tmp = File('${(await getTemporaryDirectory()).path}/poster_$_eventId.jpg');
    await tmp.writeAsBytes(bytes, flush: true);
    // Déjà réduite par PosterCompressor : on garde sa taille.
    final dims = PosterRules.dimensions(bytes);
    final side = dims == null ? 1080 : math.min(dims.width, dims.height);
    try {
      return await StorageService().saveImage(tmp, folder: 'events/$_eventId', minSide: side, quality: 90);
    } finally {
      tmp.delete().ignore();
    }
  }

  // ------------------------------------------------- Suggestions de lieu

  /// Ferme la liste et rend périmée toute réponse encore en route.
  void _closePlaceList() {
    _placeDebounce?.cancel();
    _placeRequestId++;
    if (!mounted || (_placeSuggestions.isEmpty && !_placeLoading && !_placeNoResult)) return;
    setState(() {
      _placeSuggestions = const [];
      _placeLoading = false;
      _placeNoResult = false;
    });
  }

  /// Saisie dans « Lieu » : on attend 3 caractères et une pause de 500 ms
  /// (debounce) avant de chercher. Modifier le texte après avoir choisi une
  /// suggestion efface sa position (elle ne correspondrait plus).
  void _onLocationChanged(String text) {
    _edited.add(_Field.location);
    setState(() {
      if (_placeLocated && EventRules.locationChanged(text, _placeLabel)) {
        _placeLat = null;
        _placeLng = null;
        _placeLabel = null;
      }
    });
    _placeDebounce?.cancel();
    final query = text.trim();
    if (query.length < 3) {
      _closePlaceList();
      return;
    }
    _placeDebounce = Timer(const Duration(milliseconds: 500), () => _searchPlaces(query));
  }

  Future<void> _searchPlaces(String query) async {
    // Hors-ligne : pas de liste, le texte sera enregistré tel quel.
    if (!mounted || !context.read<EventProvider>().isOnline) return;
    final id = ++_placeRequestId;
    setState(() {
      _placeLoading = true;
      _placeNoResult = false;
    });
    final response = await _photon.search(query);
    if (!mounted || id != _placeRequestId) return; // réponse périmée : ignorée
    setState(() {
      _placeLoading = false;
      switch (response) {
        case PhotonSuccess(:final suggestions):
          _placeSuggestions = suggestions;
          _placeNoResult = suggestions.isEmpty;
        case PhotonFailure():
          // Erreur réseau / serveur : pas de liste, sans message d'erreur.
          _placeSuggestions = const [];
          _placeNoResult = false;
      }
    });
  }

  /// Suggestion choisie : on remplit le champ et on garde sa position.
  void _selectPlace(PlaceSuggestion s) {
    final text = s.label.length <= EventValidators.locationMax ? s.label : s.name;
    _locationCtrl.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    _edited.add(_Field.location);
    setState(() {
      _placeLat = s.latitude;
      _placeLng = s.longitude;
      _placeLabel = text;
    });
    _closePlaceList();
    _locationFocus.unfocus();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) {
      _showMessage('Connectez-vous pour enregistrer un événement.');
      return;
    }
    // Après la première tentative, tous les champs affichent leurs erreurs.
    setState(() => _submitAttempted = true);
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<EventProvider>();
    final now = DateTime.now();
    final title = EventValidators.normalize(_titleCtrl.text);
    final location = EventValidators.normalize(_locationCtrl.text);

    // Prix modifié alors que des personnes sont inscrites : on confirme. Ils
    // le verront grâce au bandeau « Modifié le… » de la fiche (pas de paiement
    // ni de notification dans l'app).
    if (_isEdit && EventRules.needsPriceChangeConfirmation(widget.existing!, _priceValue)) {
      final n = widget.existing!.registeredUserIds.length;
      final newLabel = EventRules.priceLabel(widget.existing!.copyWith(price: _priceValue, clearPrice: _priceValue == null));
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Modifier le prix ?'),
          content: Text('$n inscrit(s) seront informés du nouveau prix ($newLabel) '
              'par le bandeau « Modifié le… » de l\'événement.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmer')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    // Position : seulement si une suggestion a été choisie (et pas modifiée
    // ensuite), coordonnées vérifiées. Sinon le texte libre est enregistré
    // sans coordonnées : on ne bloque jamais l'enregistrement.
    final located = _placeLocated && EventValidators.coordinates(_placeLat, _placeLng) == null;
    final lat = located ? _placeLat : null;
    final lng = located ? _placeLng : null;
    final placeNote = located ? null : "Lieu non localisé : pas de carte ni d'itinéraire.";

    // Affiche : enregistrée MAINTENANT (pas au choix). En cas d'échec,
    // l'organisateur choisit : réessayer, enregistrer sans la nouvelle
    // affiche, ou annuler (le formulaire reste rempli).
    final poster = await _ensurePosterSaved();
    if (!poster.proceed || !mounted) return;
    // Affiche finale : la nouvelle si enregistrée, sinon l'existante (sauf retirée).
    final posterUrl = poster.url ?? (_posterRemoved ? null : _existingPosterUrl);

    setState(() => _submitting = true);
    try {
      String message;
      if (_isEdit) {
        final original = widget.existing!;
        final edited = original.copyWith(
          title: title,
          description: EventValidators.normalize(_descCtrl.text),
          location: location,
          category: _category,
          startDate: _start,
          endDate: _end,
          capacity: _capacityValue,
          clearCapacity: _capacityValue == null,
          price: _priceValue,
          clearPrice: _priceValue == null,
          latitude: lat,
          longitude: lng,
          // Texte changé sans nouvelle suggestion : l'ancienne position serait fausse.
          clearCoordinates: !located,
          posterUrl: posterUrl,
          clearPoster: posterUrl == null,
        );
        await provider.updateEvent(original, edited);
        message = 'Événement modifié !';
      } else {
        // On ignore l'événement lui-même si un essai précédent a réussi.
        final others = provider.all.where((e) => e.id != _eventId).toList();
        final duplicate = EventValidators.duplicate(
            organizerId: user.id, title: title, start: _start, existing: others);
        if (duplicate != null) throw EventActionException(duplicate);
        final limit = EventValidators.dailyLimit(organizerId: user.id, existing: others, now: now);
        if (limit != null) throw EventActionException(limit);

        final draft = EventModel(
          id: _eventId,
          organizerId: user.id,
          organizerName: user.fullName,
          title: title,
          description: EventValidators.normalize(_descCtrl.text),
          category: _category!,
          startDate: _start,
          endDate: _end,
          location: location,
          latitude: lat,
          longitude: lng,
          capacity: _capacityValue,
          price: _priceValue,
          posterUrl: posterUrl,
        );
        await provider.createEvent(draft);
        message = 'Événement créé !';
      }
      if (!mounted) return;
      _saved = true;
      _showMessage(placeNote == null ? message : '$message $placeNote');
      Navigator.pop(context);
    } on EventActionException catch (e) {
      if (mounted) _showMessage(e.message);
    } catch (e) {
      debugPrint('Enregistrement événement échoué : $e');
      if (mounted) _showMessage("Impossible d'enregistrer l'événement. Réessayez.");
    } finally {
      // Toujours réactiver le bouton, que l'enregistrement réussisse ou non.
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final registeredCount = widget.existing?.registeredUserIds.length ?? 0;

    // Clavier fermé (bouton retour Android) : on ferme aussi la liste.
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    if (_lastKeyboardInset > 0 && keyboardInset == 0 && _placeSuggestions.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _closePlaceList());
    }
    _lastKeyboardInset = keyboardInset;

    return PopScope(
      canPop: false, // on décide nous-mêmes dans _confirmLeave
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _saved) return;
        _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_isEdit ? "Modifier l'événement" : 'Créer un événement')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PosterPicker(
                  bytes: _posterBytes,
                  existingUrl: _posterRemoved ? null : _existingPosterUrl,
                  preparing: _posterPreparing,
                  enabled: !_submitting,
                  onPick: _pickPoster,
                  onRemove: _hasPoster ? _removePoster : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleCtrl,
                  focusNode: _titleFocus,
                  autovalidateMode: _modeFor(_Field.title),
                  onChanged: (_) => _edited.add(_Field.title),
                  maxLength: EventValidators.titleMax,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _descFocus.requestFocus(),
                  decoration: const InputDecoration(labelText: "Titre de l'événement", errorMaxLines: 2),
                  validator: EventValidators.title,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _descCtrl,
                  focusNode: _descFocus,
                  autovalidateMode: _modeFor(_Field.description),
                  onChanged: (_) => _edited.add(_Field.description),
                  minLines: 3,
                  maxLines: 6,
                  maxLength: EventValidators.descriptionMax, // compteur « 123/1000 »
                  // Entrée = retour à la ligne (texte long) ; on passe au champ
                  // suivant en touchant « Lieu ».
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(labelText: 'Description', errorMaxLines: 2),
                  validator: EventValidators.description,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _locationCtrl,
                  focusNode: _locationFocus,
                  autovalidateMode: _modeFor(_Field.location),
                  onChanged: _onLocationChanged,
                  maxLength: EventValidators.locationMax,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _capacityFocus.requestFocus(),
                  decoration: InputDecoration(
                    labelText: 'Lieu',
                    prefixIcon: const Icon(Icons.place_outlined),
                    // Petit indicateur pendant la recherche, coche verte une fois localisé.
                    suffixIcon: _placeLoading
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : (_placeLocated
                            ? Tooltip(
                                message: 'Lieu localisé',
                                child: Icon(Icons.check_circle, color: t.success),
                              )
                            : null),
                    helperText: _placeLocated
                        ? 'Lieu localisé'
                        : (_locationCtrl.text.trim().isEmpty
                            ? null
                            : "Choisissez une suggestion pour activer la carte et l'itinéraire"),
                    helperStyle: _placeLocated
                        ? TextStyle(color: t.success, fontWeight: FontWeight.w600)
                        : null,
                    helperMaxLines: 2,
                    errorMaxLines: 2,
                  ),
                  validator: EventValidators.location,
                ),
                // Toucher une suggestion ne doit pas faire perdre le focus au
                // champ avant le choix : la liste fait partie de sa zone.
                if (_placeSuggestions.isNotEmpty || _placeNoResult)
                  TextFieldTapRegion(
                    child: _PlaceSuggestionList(
                      suggestions: _placeSuggestions,
                      noResult: _placeNoResult,
                      onSelected: _selectPlace,
                    ),
                  ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _capacityCtrl,
                  focusNode: _capacityFocus,
                  autovalidateMode: _modeFor(_Field.capacity),
                  onChanged: (_) => _edited.add(_Field.capacity),
                  maxLength: 4, // 5000 max : 4 chiffres suffisent
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _priceFocus.requestFocus(),
                  decoration: InputDecoration(
                    labelText: 'Capacité (optionnelle)',
                    helperText: registeredCount > 0
                        ? 'Vide = illimitée · minimum $registeredCount (déjà inscrits)'
                        : 'Vide = places illimitées',
                    prefixIcon: const Icon(Icons.event_seat_outlined),
                    counterText: '', // pas de compteur « 0/4 » pour un nombre
                    errorMaxLines: 2,
                  ),
                  validator: (v) => EventValidators.capacity(v, registeredCount: registeredCount),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _priceCtrl,
                  focusNode: _priceFocus,
                  autovalidateMode: _modeFor(_Field.price),
                  onChanged: (_) => _edited.add(_Field.price),
                  maxLength: 7, // « 1000,00 »
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  // Chiffres, virgule ou point (la virgule est normalisée en point).
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Prix (TND)',
                    hintText: 'Gratuit',
                    helperText: 'Vide = gratuit · informatif, payé sur place',
                    prefixIcon: Icon(Icons.sell_outlined),
                    counterText: '',
                    errorMaxLines: 2,
                  ),
                  validator: EventValidators.price,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: _categoryFieldKey,
                  initialValue: _category,
                  autovalidateMode: _modeFor(_Field.category),
                  decoration: const InputDecoration(labelText: 'Catégorie', errorMaxLines: 2),
                  // Prend toute la largeur : pas de débordement à 320 px / grand texte.
                  isExpanded: true,
                  items: EventCategories.all
                      .map((c) => DropdownMenuItem(
                          value: c, child: Text(c, maxLines: 1, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _category = v;
                    _touched.add(_Field.category);
                  }),
                  validator: EventValidators.category,
                ),
                if (_showSuggestion)
                  _CategorySuggestionChip(
                    suggestion: _suggestion!,
                    onApply: _applySuggestion,
                    onDismiss: _dismissSuggestion,
                  ),
                const SizedBox(height: 16),
                FormField<DateTime>(
                  autovalidateMode: _modeFor(_Field.start),
                  initialValue: _start,
                  // En modification, un début inchangé n'est pas revérifié
                  // (sinon on ne pourrait plus corriger le titre 10 min avant).
                  validator: (v) => (_isEdit && v == widget.existing!.startDate)
                      ? null
                      : EventValidators.start(v, now: DateTime.now()),
                  builder: (field) => _DateTimeButton(
                    label: 'Début',
                    value: _start,
                    error: field.errorText,
                    onTap: () => _pickStart(field),
                  ),
                ),
                const SizedBox(height: 10),
                FormField<DateTime>(
                  key: _endFieldKey,
                  autovalidateMode: _modeFor(_Field.end),
                  initialValue: _end,
                  validator: (v) => EventValidators.end(_start, v),
                  builder: (field) => _DateTimeButton(
                    label: 'Fin',
                    value: _end,
                    error: field.errorText,
                    onTap: () => _pickEnd(field),
                  ),
                ),
                const SizedBox(height: 24),
                PrimaryButton(
                  label: _isEdit ? 'Enregistrer les modifications' : "Créer l'événement",
                  isLoading: _submitting, // désactivé pendant l'enregistrement
                  onPressed: _submit,
                ),
                if (_posterUploading)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text("Enregistrement de l'affiche…",
                        textAlign: TextAlign.center, style: TextStyle(color: t.textSecondary)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Zone d'affiche (16:9) en haut du formulaire : « Ajouter une affiche »,
/// puis l'aperçu avec « Changer » / « Retirer » et le poids après compression.
class _PosterPicker extends StatelessWidget {
  final Uint8List? bytes; // nouvelle affiche choisie (pas encore envoyée)
  final String? existingUrl; // affiche déjà enregistrée (modification)
  final bool preparing;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback? onRemove;
  const _PosterPicker({
    required this.bytes,
    required this.existingUrl,
    required this.preparing,
    required this.enabled,
    required this.onPick,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final hasImage = bytes != null || existingUrl != null;
    // Zone de hauteur fixe (16/9) : à 320 px avec un grand texte, le contenu
    // est réduit pour tenir au lieu de déborder.
    final placeholder = Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_photo_alternate_outlined, size: 36, color: t.primary),
              const SizedBox(height: 6),
              Text('Ajouter une affiche', style: TextStyle(fontWeight: FontWeight.w700, color: t.primary)),
              const SizedBox(height: 2),
              Text('JPG ou PNG, 5 Mo maximum (optionnel)', style: TextStyle(fontSize: 12, color: t.textSecondary)),
            ],
          ),
        ),
      ),
    );

    Widget content;
    if (preparing) {
      content = const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 8),
          Text("Préparation de l'affiche…"),
        ]),
      );
    } else if (bytes != null) {
      content = Semantics(image: true, label: 'Affiche choisie', child: Image.memory(bytes!, fit: BoxFit.cover));
    } else if (existingUrl != null) {
      content = Semantics(
        image: true,
        label: "Affiche actuelle de l'événement",
        child: AppImage(
          url: existingUrl!,
          fit: BoxFit.cover,
          placeholder: (_) => const Center(child: CircularProgressIndicator()),
          error: (_) => placeholder,
        ),
      );
    } else {
      content = placeholder;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Material(
            color: t.primary.withValues(alpha: 0.05),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: t.outline),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              // Zone vide : un toucher ouvre la galerie.
              onTap: enabled && !preparing && !hasImage ? onPick : null,
              child: content,
            ),
          ),
        ),
        if (hasImage && !preparing) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: bytes != null
                    ? Text('Affiche compressée : ${PosterRules.formatSize(bytes!.length)}',
                        maxLines: 2, style: TextStyle(fontSize: 12.5, color: t.textSecondary))
                    : const SizedBox.shrink(),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(44, 48)),
                onPressed: enabled ? onPick : null,
                icon: const Icon(Icons.swap_horiz_rounded),
                label: const Text('Changer'),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(44, 48), foregroundColor: t.danger),
                onPressed: enabled ? onRemove : null,
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Retirer'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Liste des suggestions de lieu sous le champ : épingle, nom en gras,
/// ligne grise (rue / quartier, ville, pays). Ou « Aucun lieu trouvé ».
/// Puce « Suggestion : Sport (87 %) » sous la catégorie. Rien n'est appliqué
/// sans un appui sur « Appliquer ». Le texte passe à la ligne et les boutons
/// se replient sous le texte si la place manque (320 px, grand texte).
class _CategorySuggestionChip extends StatelessWidget {
  final CategorySuggestion suggestion;
  final VoidCallback onApply;
  final VoidCallback onDismiss;
  const _CategorySuggestionChip({required this.suggestion, required this.onApply, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final percent = (suggestion.probability * 100).round();
    // Espaces insécables : « 87 % » et « : » ne sont jamais coupés en fin de ligne.
    final label = 'Suggestion : ${suggestion.category} ($percent %)';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
          decoration: BoxDecoration(
            color: t.primarySoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(Icons.auto_awesome_outlined, size: 18, color: t.onPrimarySoft),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(label,
                        style: TextStyle(color: t.onPrimarySoft, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              OverflowBar(
                alignment: MainAxisAlignment.end,
                overflowAlignment: OverflowBarAlignment.end,
                children: [
                  TextButton(
                    onPressed: onDismiss,
                    style: TextButton.styleFrom(foregroundColor: t.textSecondary),
                    child: const Text('Ignorer'),
                  ),
                  TextButton(
                    onPressed: onApply,
                    style: TextButton.styleFrom(foregroundColor: t.onPrimarySoft),
                    child: const Text('Appliquer'),
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

class _PlaceSuggestionList extends StatelessWidget {
  final List<PlaceSuggestion> suggestions;
  final bool noResult;
  final ValueChanged<PlaceSuggestion> onSelected;
  const _PlaceSuggestionList({required this.suggestions, required this.noResult, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Material(
        color: t.surface,
        elevation: 3,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (noResult)
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text('Aucun lieu trouvé : le texte sera enregistré tel quel',
                    style: TextStyle(color: t.textSecondary)),
              ),
            for (final s in suggestions)
              Semantics(
                button: true,
                label: s.secondary.isEmpty ? s.name : '${s.name}, ${s.secondary}',
                excludeSemantics: true,
                child: InkWell(
                  onTap: () => onSelected(s),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 52),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      child: Row(
                        children: [
                          Icon(Icons.place_outlined, size: 20, color: t.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(s.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                                if (s.secondary.isNotEmpty)
                                  Text(s.secondary,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 12.5, color: t.textSecondary)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            // Données OpenStreetMap via Photon : attribution demandée.
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 2, 14, 8),
              child: Text('Suggestions : Photon · © OpenStreetMap contributors',
                  style: TextStyle(fontSize: 10.5, color: t.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bouton « Début » / « Fin » qui affiche la date choisie et l'erreur éventuelle.
class _DateTimeButton extends StatelessWidget {
  final String label;
  final DateTime value;
  final String? error;
  final VoidCallback onTap;
  const _DateTimeButton({required this.label, required this.value, required this.error, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            side: error == null ? null : BorderSide(color: errorColor),
          ),
          icon: const Icon(Icons.schedule_rounded, size: 18),
          label: Text('$label : ${DateFormat("EEE d MMM yyyy 'à' HH:mm", 'fr_FR').format(value)}'),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Text(error!,
                maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: errorColor, fontSize: 12)),
          ),
      ],
    );
  }
}
