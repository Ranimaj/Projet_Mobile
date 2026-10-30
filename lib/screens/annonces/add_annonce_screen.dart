import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_tokens.dart';
import '../../models/annonce_model.dart';
import '../../providers/annonce_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/filter_chip_pill.dart';
import '../../widgets/location_picker_field.dart';
import '../../widgets/primary_button.dart';

/// Publier OU modifier une annonce campus (si [annonce] est fourni = édition).
///  - "Officielle" (admin uniquement) => épinglée automatiquement ;
///  - ciblage par filière / année => notification push ciblée (Cloud Function).
class AddAnnonceScreen extends StatefulWidget {
  final AnnonceModel? annonce;
  const AddAnnonceScreen({super.key, this.annonce});

  @override
  State<AddAnnonceScreen> createState() => _AddAnnonceScreenState();
}

class _AddAnnonceScreenState extends State<AddAnnonceScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  late String _category;
  late bool _isUrgent;
  late bool _sendPush;
  late final Set<String> _majors;
  late final Set<String> _years;
  bool _submitting = false;
  String? _locationName;
  double? _lat;
  double? _lon;

  bool get _isEdit => widget.annonce != null;
  bool get _isLost => _category == 'Perdu & Trouvé';

  @override
  void initState() {
    super.initState();
    final a = widget.annonce;
    _titleCtrl = TextEditingController(text: a?.title ?? '');
    _contentCtrl = TextEditingController(text: a?.content ?? '');
    _category = a?.category ?? 'Générale';
    _isUrgent = a?.isUrgent ?? false;
    _sendPush = a?.sendPush ?? false;
    _majors = {...?a?.targetMajors};
    _years = {...?a?.targetYears};
    _locationName = a?.locationName;
    _lat = a?.latitude;
    _lon = a?.longitude;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;

    setState(() => _submitting = true);
    final provider = context.read<AnnonceProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      if (_isEdit) {
        await provider.updateAnnonce(
          widget.annonce!,
          title: _titleCtrl.text.trim(),
          content: _contentCtrl.text.trim(),
          category: _category,
          isUrgent: _isUrgent,
          targetMajors: _majors.toList(),
          targetYears: _years.toList(),
          locationName: _isLost ? _locationName : null,
          latitude: _isLost ? _lat : null,
          longitude: _isLost ? _lon : null,
        );
      } else {
        await provider.createAnnonce(AnnonceModel(
          id: '',
          authorId: user.id,
          authorName: user.fullName,
          title: _titleCtrl.text.trim(),
          content: _contentCtrl.text.trim(),
          category: _category,
          isUrgent: _isUrgent,
          sendPush: _sendPush,
          targetMajors: _majors.toList(),
          targetYears: _years.toList(),
          locationName: _isLost ? _locationName : null,
          latitude: _isLost ? _lat : null,
          longitude: _isLost ? _lon : null,
          createdAt: DateTime.now(),
        ));
      }
      messenger.showSnackBar(SnackBar(
        content: Text(_isEdit ? 'Annonce modifiée.' : 'Annonce publiée !'),
      ));
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Impossible d'enregistrer l'annonce. Réessayez.")),
      );
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final isAdmin = context.watch<AnnonceProvider>().isAdmin;
    final categories =
        AppConstants.annonceCategories.where((c) => c != 'Officielle' || isAdmin).toList();
    if (!categories.contains(_category)) _category = categories.first;

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? "Modifier l'annonce" : 'Publier une annonce')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _titleCtrl,
                maxLength: 100,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Titre'),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return 'Titre requis';
                  if (t.length < 3) return 'Titre trop court (3 caractères min.)';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _contentCtrl,
                maxLines: 6,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration:
                    const InputDecoration(labelText: 'Contenu', alignLabelWithHint: true),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return 'Contenu requis';
                  if (t.length < 10) return 'Contenu trop court (10 caractères min.)';
                  return null;
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Catégorie'),
                items: categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              if (_category == 'Officielle')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Icon(Icons.push_pin_rounded, size: 16, color: t.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Les annonces officielles sont épinglées automatiquement en tête du fil.',
                        style: text.bodySmall!.copyWith(color: t.onPrimarySoft),
                      ),
                    ),
                  ]),
                ),
              if (_isLost) ...[
                const SizedBox(height: 14),
                LocationPickerField(
                  initialName: _locationName,
                  onChanged: (p) => setState(() {
                    _locationName = p?.name;
                    _lat = p?.latitude;
                    _lon = p?.longitude;
                  }),
                ),
              ],
              const SizedBox(height: 18),
              _sectionTitle('Destinataires'),
              const SizedBox(height: 4),
              Text(
                'Sans sélection, l’annonce concerne tout le campus. '
                'Sinon, seuls les étudiants des filières / années choisies sont notifiés.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              _chipGroup('Filières', AppConstants.campusMajors, _majors),
              const SizedBox(height: 10),
              _chipGroup('Années', AppConstants.campusYears, _years),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Annonce urgente', style: text.titleSmall),
                subtitle: Text('Badge « Urgent » dans le fil', style: text.bodySmall),
                value: _isUrgent,
                onChanged: (v) => setState(() {
                  _isUrgent = v;
                  if (v && !_isEdit) _sendPush = true; // une urgence est notifiée par défaut
                }),
              ),
              if (!_isEdit)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Envoyer une notification push', style: text.titleSmall),
                  subtitle: Text(
                    _majors.isEmpty && _years.isEmpty
                        ? 'À tous les étudiants du campus'
                        : 'Uniquement aux destinataires ciblés',
                    style: text.bodySmall,
                  ),
                  value: _sendPush,
                  onChanged: (v) => setState(() => _sendPush = v),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'La notification push n’est envoyée qu’à la première publication.',
                    style: text.bodySmall,
                  ),
                ),
              const SizedBox(height: 16),
              PrimaryButton(
                label: _isEdit ? 'Enregistrer' : 'Publier',
                isLoading: _submitting,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) =>
      Text(text, style: Theme.of(context).textTheme.titleMedium);

  Widget _chipGroup(String label, List<String> options, Set<String> selected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 2),
        Wrap(
          spacing: 8,
          children: options
              .map((o) => FilterChipPill(
                    label: o,
                    selected: selected.contains(o),
                    onTap: () => setState(
                        () => selected.contains(o) ? selected.remove(o) : selected.add(o)),
                  ))
              .toList(),
        ),
      ],
    );
  }
}
