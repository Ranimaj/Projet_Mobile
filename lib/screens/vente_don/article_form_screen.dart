import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/layout.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/geo.dart';
import '../../models/article_model.dart';
import '../../providers/article_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/bottom_action_bar.dart';
import '../../widgets/filter_chip_pill.dart';
import '../../services/ai/article_ai.dart';
import '../../services/ai/category_mapper.dart';
import '../../services/ai/moderation.dart';
import '../../widgets/pill_button.dart';
import 'widgets/ai_assistant_card.dart';
import 'widgets/article_photo.dart';

/// Sélection de photos (remplaçable dans les tests).
typedef PickImages = Future<List<File>> Function();

Future<List<File>> _pickFromGallery() async {
  final picked = await ImagePicker().pickMultiImage(imageQuality: 85);
  return [for (final x in picked) File(x.path)];
}

/// Validation des champs du formulaire (exposée pour les tests).
class ArticleFormValidators {
  ArticleFormValidators._();

  static String? title(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Titre requis';
    if (s.length < 3) return 'Au moins 3 caractères';
    if (s.length > 80) return '80 caractères maximum';
    return null;
  }

  static String? description(String? v) {
    final s = v?.trim() ?? '';
    if (s.isEmpty) return 'Description requise';
    if (s.length < 10) return 'Décris l\'objet en au moins 10 caractères';
    if (s.length > 1000) return '1000 caractères maximum';
    return null;
  }

  /// Prix en DT, virgule acceptée. Ignoré pour un don.
  static String? price(String? v, {required bool isFree}) {
    if (isFree) return null;
    final p = parsePrice(v);
    if (p == null) return 'Prix invalide';
    if (p <= 0) return 'Le prix doit être positif (ou coche « Don gratuit »)';
    if (p > 100000) return 'Prix trop élevé';
    return null;
  }

  static double? parsePrice(String? v) =>
      double.tryParse((v ?? '').trim().replaceAll(',', '.').replaceAll(' ', ''));
}

/// BF4 — publier un nouvel article ou modifier un article existant
/// ([article] non nul) : titre, description, catégorie, prix ou don, jusqu'à
/// 6 photos (compressées à l'envoi) et position facultative pour la
/// recherche par distance. Hors-ligne, l'article et ses photos restent sur le
/// téléphone, apparaissent tout de suite dans la liste et partent au retour
/// du réseau (BF14).
class ArticleFormScreen extends StatefulWidget {
  final ArticleModel? article;
  final PickImages? pickImages;

  /// Services IA (reconnaissance de photo, rédaction) ; remplaçables en test.
  final ArticleAi? ai;

  const ArticleFormScreen({super.key, this.article, this.pickImages, this.ai});

  bool get isEditing => article != null;

  @override
  State<ArticleFormScreen> createState() => _ArticleFormScreenState();
}

class _ArticleFormScreenState extends State<ArticleFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _titleCtrl = TextEditingController(text: widget.article?.title ?? '');
  late final _descCtrl = TextEditingController(text: widget.article?.description ?? '');
  late final _priceCtrl = TextEditingController(
    text: widget.article == null || widget.article!.isFree
        ? ''
        : widget.article!.priceLabel.replaceAll(' DT', ''),
  );
  late String _category = widget.article?.category ?? AppConstants.articleCategories.first;
  late bool _isFree = widget.article?.isFree ?? false;
  late final List<String> _kept = [...?widget.article?.imageUrls];
  final List<File> _newImages = [];
  late GeoPoint2? _location = widget.article?.location;
  bool _locating = false;
  bool _submitting = false;

  // --- IA ---
  ArticleAi get _ai => widget.ai ?? ArticleAi.instance;
  bool _analyzing = false;
  bool _analysisFailed = false;
  CategorySuggestion? _suggestion;
  List<String>? _labels;
  bool _categoryTouched = false;
  bool _writing = false;
  List<String> _keywords = const [];

  int get _photoCount => _kept.length + _newImages.length;

  @override
  void initState() {
    super.initState();
    _titleCtrl.addListener(_onTitleChanged);
  }

  String _lastTitle = '';
  void _onTitleChanged() {
    // Recalcule le prix conseillé quand le titre change vraiment.
    if (_titleCtrl.text.trim() == _lastTitle) return;
    _lastTitle = _titleCtrl.text.trim();
    if (mounted) setState(() {});
  }

  /// Reconnaît l'objet sur [photo] : catégorie, mots-clés et étiquettes.
  Future<void> _analyze(File photo) async {
    setState(() {
      _analyzing = true;
      _analysisFailed = false;
    });
    try {
      final tags = await _ai.tagger.tag(photo);
      if (!mounted) return;
      final suggestion = suggestCategory(tags);
      setState(() {
        _analyzing = false;
        _labels = labelsForSearch(tags);
        _suggestion = suggestion;
        _keywords = suggestion?.keywords ?? const [];
        _analysisFailed = suggestion == null;
        if (suggestion != null && !_categoryTouched) _category = suggestion.category;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _analyzing = false;
        _analysisFailed = true;
      });
    }
  }

  void _addKeyword(String k) {
    final current = _titleCtrl.text.trim();
    if (current.toLowerCase().contains(k.toLowerCase())) return;
    final next = current.isEmpty ? '${k[0].toUpperCase()}${k.substring(1)}' : '$current $k';
    _titleCtrl.text = next.length > 80 ? next.substring(0, 80) : next;
  }

  Future<void> _writeDescription() async {
    final online = context.read<ArticleProvider>().isOnline;
    if (!online || _writing) return;
    setState(() => _writing = true);
    try {
      final text = await _ai.writer.write(DescriptionRequest(
        title: _titleCtrl.text.trim().isEmpty ? 'Objet' : _titleCtrl.text.trim(),
        category: _category,
        price: _isFree ? null : ArticleFormValidators.parsePrice(_priceCtrl.text),
        keywords: _keywords,
        photo: _newImages.isEmpty ? null : _newImages.first,
      ));
      if (!mounted) return;
      _descCtrl.text = text;
      _snack('Description proposée par l\'IA : relis-la et modifie-la si besoin.');
    } catch (e) {
      debugPrint('[IA] Gemini a échoué : $e');
      if (mounted) {
        _snack(kDebugMode
            ? 'IA indisponible : $e'
            : 'L\'IA n\'a pas pu rédiger la description. Réessaie plus tard.');
      }
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  /// Vérifie l'annonce (objets interdits, insultes, coordonnées…). Renvoie
  /// false si la publication doit être annulée.
  Future<bool> _passesModeration(double? price) async {
    final result = moderateArticle(
      title: _titleCtrl.text,
      description: _descCtrl.text,
      category: _category,
      price: price,
    );
    if (result.ok) return true;
    if (result.blocked) {
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          key: const Key('moderation-blocked'),
          title: const Text('Annonce refusée'),
          content: Text(result.messages(ModerationLevel.block).join('\n')),
          actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Modifier'))],
        ),
      );
      return false;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        key: const Key('moderation-warning'),
        title: const Text('Vérifie ton annonce'),
        content: Text(result.messages(ModerationLevel.warn).join('\n')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Modifier')),
          TextButton(
            key: const Key('publish-anyway'),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Publier quand même'),
          ),
        ],
      ),
    );
    return go == true;
  }

  @override
  void dispose() {
    _titleCtrl.removeListener(_onTitleChanged);
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _addPhotos() async {
    final room = ArticleModel.maxPhotos - _photoCount;
    if (room <= 0) return;
    final picked = await (widget.pickImages ?? _pickFromGallery)();
    if (!mounted || picked.isEmpty) return;
    final coverBefore = _kept.isEmpty && _newImages.isEmpty;
    setState(() => _newImages.addAll(picked.take(room)));
    if (picked.length > room) _snack('${ArticleModel.maxPhotos} photos maximum.');
    // La photo de couverture sert à reconnaître l'objet.
    if (coverBefore || _suggestion == null) await _analyze(_newImages.first);
  }

  Future<void> _locate() async {
    final provider = context.read<ArticleProvider>();
    setState(() => _locating = true);
    final ok = await provider.locateUser();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (ok) _location = provider.userPosition;
    });
    final error = provider.locationError;
    if (!ok && error != null) _snack(error);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<ArticleProvider>();
    final user = context.read<AuthProvider>().currentUser;
    if (user == null) return;
    final price = _isFree ? null : ArticleFormValidators.parsePrice(_priceCtrl.text);
    if (!await _passesModeration(price)) return;
    if (!mounted) return;
    setState(() => _submitting = true);
    try {
      final original = widget.article;
      if (original != null) {
        await provider.editArticle(
          original,
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          category: _category,
          price: price,
          keptUrls: _kept,
          newImages: _newImages,
          location: _location,
          removeLocation: _location == null && original.hasLocation,
          labels: _labels,
        );
      } else {
        await provider.createArticle(
          draft: ArticleModel(
            id: '',
            ownerId: user.id,
            ownerName: user.fullName,
            title: _titleCtrl.text.trim(),
            description: _descCtrl.text.trim(),
            price: price,
            category: _category,
            latitude: _location?.latitude,
            longitude: _location?.longitude,
            createdAt: DateTime.now(),
            labels: _labels ?? const [],
          ),
          imageFiles: _newImages,
        );
      }
      if (!mounted) return;
      final waiting = !provider.isOnline || provider.pendingPhotoArticles > 0;
      _snack(widget.isEditing
          ? 'Article modifié !'
          : waiting
              ? 'Article publié ! Il sera envoyé au retour du réseau.'
              : 'Article publié !');
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _snack('Échec de l\'enregistrement. Réessaie.');
    }
  }

  Widget _photoTile({required Widget image, required VoidCallback onRemove, required String label}) {
    return SizedBox(
      width: 88,
      height: 88,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(borderRadius: BorderRadius.circular(14), child: image),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Semantics(
              button: true,
              label: label,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const SizedBox(
                  width: 48,
                  height: 48,
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: EdgeInsets.all(4),
                      child: CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final provider = context.watch<ArticleProvider>();
    final online = provider.isOnline;
    final advice = _isFree
        ? null
        : provider.priceAdviceFor(
            title: _titleCtrl.text,
            category: _category,
            excludeId: widget.article?.id,
          );
    final suggestion = _suggestion;

    return Scaffold(
      appBar: AppBar(title: Text(widget.isEditing ? 'Modifier l\'article' : 'Publier un article')),
      bottomNavigationBar: BottomActionBar(
        child: PillButton(
          key: const Key('submit-article'),
          label: widget.isEditing ? 'Enregistrer' : 'Publier',
          icon: widget.isEditing ? Icons.check_rounded : Icons.send_rounded,
          isLoading: _submitting,
          onPressed: _submit,
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(kPagePadding, 16, kPagePadding, 120),
          children: [
            Text('Photos ($_photoCount/${ArticleModel.maxPhotos})', style: text.titleMedium),
            const SizedBox(height: 4),
            Text('La première photo sert de couverture. Elles sont compressées avant l\'envoi.',
                style: text.bodySmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final url in List.of(_kept))
                  _photoTile(
                    label: 'Retirer la photo',
                    image: ArticlePhoto(url: url),
                    onRemove: () => setState(() => _kept.remove(url)),
                  ),
                for (final file in List.of(_newImages))
                  _photoTile(
                    label: 'Retirer la photo',
                    image: ArticlePhoto(url: file.path),
                    onRemove: () => setState(() => _newImages.remove(file)),
                  ),
                if (_photoCount < ArticleModel.maxPhotos)
                  Semantics(
                    button: true,
                    label: 'Ajouter des photos',
                    child: InkWell(
                      key: const Key('add-photos'),
                      borderRadius: BorderRadius.circular(14),
                      onTap: _addPhotos,
                      child: Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: t.primarySoft,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: t.primary.withValues(alpha: 0.4)),
                        ),
                        child: Icon(Icons.add_a_photo_outlined, color: t.primary),
                      ),
                    ),
                  ),
              ],
            ),
            if (!online) ...[
              const SizedBox(height: 8),
              Text('Hors ligne : l\'article et ses photos sont gardés sur le téléphone et partiront au retour du réseau.',
                  style: text.bodySmall?.copyWith(color: t.warning)),
            ],
            const SizedBox(height: 16),
            AiAssistantCard(
              analyzing: _analyzing,
              analysisFailed: _analysisFailed,
              suggestion: suggestion,
              categoryApplied: suggestion != null && suggestion.category == _category,
              onApplyCategory: suggestion == null
                  ? null
                  : () => setState(() {
                        _category = suggestion.category;
                        _categoryTouched = true;
                      }),
              onKeyword: _addKeyword,
              priceAdvice: advice,
              isFree: _isFree,
              onUsePrice: advice == null
                  ? null
                  : () => setState(() => _priceCtrl.text = advice.suggested.round().toString()),
              writing: _writing,
              online: online,
              onWrite: _writeDescription,
            ),
            const SizedBox(height: 20),
            TextFormField(
              key: const Key('field-title'),
              controller: _titleCtrl,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Titre', hintText: 'Ex. Calculatrice TI-83'),
              validator: ArticleFormValidators.title,
            ),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('field-description'),
              controller: _descCtrl,
              minLines: 3,
              maxLines: 6,
              maxLength: 1000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'État, marque, lieu de remise…',
                alignLabelWithHint: true,
              ),
              validator: ArticleFormValidators.description,
            ),
            const SizedBox(height: 12),
            Text('Catégorie', style: text.titleMedium),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final c in AppConstants.articleCategories)
                  FilterChipPill(
                    key: ValueKey('category-$c'),
                    label: c,
                    selected: _category == c,
                    onTap: () => setState(() {
                      _category = c;
                      _categoryTouched = true;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const Key('field-free'),
              contentPadding: EdgeInsets.zero,
              title: Text('Don gratuit', style: text.bodyLarge),
              subtitle: Text('L\'objet est donné sans contrepartie', style: text.bodySmall),
              value: _isFree,
              onChanged: (v) => setState(() => _isFree = v),
            ),
            if (!_isFree)
              TextFormField(
                key: const Key('field-price'),
                controller: _priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Prix', suffixText: 'DT'),
                validator: (v) => ArticleFormValidators.price(v, isFree: _isFree),
              ),
            const SizedBox(height: 20),
            Text('Position', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Facultatif : permet aux autres étudiants de trouver ton objet par distance.',
              style: text.bodySmall,
            ),
            const SizedBox(height: 10),
            if (_location != null)
              Container(
                key: const Key('location-set'),
                padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
                decoration: BoxDecoration(
                  color: t.successSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.place_rounded, color: t.success),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Position ajoutée', style: text.labelLarge)),
                    TextButton(
                      key: const Key('remove-location'),
                      onPressed: () => setState(() => _location = null),
                      child: const Text('Retirer'),
                    ),
                  ],
                ),
              )
            else
              PillButton(
                key: const Key('add-location'),
                label: 'Ajouter ma position',
                icon: Icons.my_location_rounded,
                style: PillStyle.ghost,
                isLoading: _locating,
                onPressed: _locate,
              ),
          ],
        ),
      ),
    );
  }
}
