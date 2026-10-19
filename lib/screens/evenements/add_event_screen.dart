import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_constants.dart';
import '../../models/event_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/event_provider.dart';
import '../../widgets/primary_button.dart';
import 'event_validators.dart';

/// BF8.3 / BF8.4 — un seul formulaire pour créer OU modifier un événement.
/// Création si [existing] est null, modification sinon.
class AddEventScreen extends StatefulWidget {
  final EventModel? existing;
  const AddEventScreen({super.key, this.existing});

  @override
  State<AddEventScreen> createState() => _AddEventScreenState();
}

class _AddEventScreenState extends State<AddEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _endFieldKey = GlobalKey<FormFieldState<DateTime>>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _capacityCtrl = TextEditingController();
  final _descFocus = FocusNode();
  final _locationFocus = FocusNode();
  final _capacityFocus = FocusNode();

  /// Id généré une seule fois à l'ouverture et réutilisé à chaque nouvel
  /// essai : un réseau lent ne peut jamais créer deux fois l'événement.
  late final String _eventId;
  String? _category;
  String? _initialCategory;
  late DateTime _start;
  late DateTime _end;
  bool _submitting = false;
  bool _saved = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _eventId = e?.id ?? const Uuid().v4();
    if (e != null) {
      _titleCtrl.text = e.title;
      _descCtrl.text = e.description;
      _locationCtrl.text = e.location;
      _capacityCtrl.text = e.capacity?.toString() ?? '';
      // Une ancienne catégorie hors liste oblige à en choisir une valide.
      _category = AppConstants.eventCategories.contains(e.category) ? e.category : null;
      _initialCategory = _category;
      _start = e.startDate;
      _end = e.endDate;
    } else {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      _category = AppConstants.eventCategories.first;
      _start = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 14, 0);
      _end = _start.add(EventModel.defaultDuration);
    }
  }

  @override
  void dispose() {
    for (final c in [_titleCtrl, _descCtrl, _locationCtrl, _capacityCtrl]) {
      c.dispose();
    }
    for (final f in [_descFocus, _locationFocus, _capacityFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  int? get _capacityValue {
    final v = _capacityCtrl.text.trim();
    return v.isEmpty ? null : int.parse(v);
  }

  /// Le formulaire contient-il des modifications non enregistrées ?
  bool get _isDirty {
    final e = widget.existing;
    String n(String s) => EventValidators.normalize(s);
    if (e == null) {
      return [_titleCtrl, _descCtrl, _locationCtrl, _capacityCtrl].any((c) => n(c.text).isNotEmpty);
    }
    return n(_titleCtrl.text) != e.title ||
        n(_descCtrl.text) != e.description ||
        n(_locationCtrl.text) != e.location ||
        _category != _initialCategory ||
        _start != e.startDate ||
        _end != e.endDate ||
        _capacityCtrl.text.trim() != (e.capacity?.toString() ?? '');
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
    });
    field.didChange(picked);
    _endFieldKey.currentState?.didChange(_end);
  }

  Future<void> _pickEnd(FormFieldState<DateTime> field) async {
    final first = DateTime(_start.year, _start.month, _start.day);
    final picked = await _pickDateTime(_end, first: first, last: first.add(const Duration(days: 4)));
    if (picked == null) return;
    setState(() => _end = picked);
    field.didChange(picked);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) {
      _showMessage('Connectez-vous pour enregistrer un événement.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<EventProvider>();
    final now = DateTime.now();
    final title = EventValidators.normalize(_titleCtrl.text);

    setState(() => _submitting = true);
    try {
      String message;
      if (_isEdit) {
        final original = widget.existing!;
        final edited = original.copyWith(
          title: title,
          description: EventValidators.normalize(_descCtrl.text),
          location: EventValidators.normalize(_locationCtrl.text),
          category: _category,
          startDate: _start,
          endDate: _end,
          capacity: _capacityValue,
          clearCapacity: _capacityValue == null,
        );
        final sentOnline = await provider.updateEvent(original, edited);
        message = sentOnline
            ? 'Événement modifié !'
            : 'Modifications enregistrées : envoi au retour du réseau.';
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
          location: EventValidators.normalize(_locationCtrl.text),
          capacity: _capacityValue,
        );
        // Le provider applique un délai max de 15 s (TimeoutException ci-dessous).
        final sentOnline = await provider.createEvent(draft);
        message = sentOnline ? 'Événement créé !' : 'Événement enregistré : publication au retour du réseau.';
      }
      if (!mounted) return;
      _saved = true;
      _showMessage(message);
      Navigator.pop(context);
    } on EventActionException catch (e) {
      if (mounted) _showMessage(e.message);
    } on TimeoutException {
      if (mounted) {
        _showMessage('Le serveur ne répond pas. Réessayez : '
            "l'événement ne sera pas créé en double.");
      }
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
    final registeredCount = widget.existing?.registeredUserIds.length ?? 0;

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
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _titleCtrl,
                  maxLength: EventValidators.titleMax,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _descFocus.requestFocus(),
                  decoration: const InputDecoration(labelText: "Titre de l'événement"),
                  validator: EventValidators.title,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _descCtrl,
                  focusNode: _descFocus,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: EventValidators.descriptionMax, // compteur « 123/1000 »
                  // Entrée = retour à la ligne (texte long) ; on passe au champ
                  // suivant en touchant « Lieu ».
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(labelText: 'Description'),
                  validator: EventValidators.description,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _locationCtrl,
                  focusNode: _locationFocus,
                  maxLength: EventValidators.locationMax,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _capacityFocus.requestFocus(),
                  decoration: const InputDecoration(labelText: 'Lieu', prefixIcon: Icon(Icons.place_outlined)),
                  validator: EventValidators.location,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _capacityCtrl,
                  focusNode: _capacityFocus,
                  maxLength: 4,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Capacité (optionnelle)',
                    helperText: registeredCount > 0
                        ? 'Vide = illimitée · minimum $registeredCount (déjà inscrits)'
                        : 'Vide = places illimitées',
                    prefixIcon: const Icon(Icons.event_seat_outlined),
                  ),
                  validator: (v) => EventValidators.capacity(v, registeredCount: registeredCount),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Catégorie'),
                  items: AppConstants.eventCategories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => _category = v),
                  validator: EventValidators.category,
                ),
                const SizedBox(height: 16),
                FormField<DateTime>(
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
              ],
            ),
          ),
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
            child: Text(error!, style: TextStyle(color: errorColor, fontSize: 12)),
          ),
      ],
    );
  }
}
