import 'package:flutter/material.dart';
import '../core/theme/app_tokens.dart';
import '../services/place_search_service.dart';

/// Champ "Lieu" avec recherche OpenStreetMap (utilisé pour "Perdu & Trouvé").
/// [onChanged] reçoit le lieu choisi, ou null s'il est effacé.
class LocationPickerField extends StatefulWidget {
  final String? initialName;
  final ValueChanged<PlaceResult?> onChanged;
  const LocationPickerField({super.key, this.initialName, required this.onChanged});

  @override
  State<LocationPickerField> createState() => _LocationPickerFieldState();
}

class _LocationPickerFieldState extends State<LocationPickerField> {
  final _service = PlaceSearchService();
  late final TextEditingController _ctrl;
  List<PlaceResult> _results = [];
  bool _loading = false;
  bool _selected = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialName ?? '');
    _selected = widget.initialName != null;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _message = null;
      _results = [];
    });
    try {
      final r = await _service.search(_ctrl.text);
      if (!mounted) return;
      setState(() {
        _results = r;
        if (r.isEmpty) _message = 'Aucun lieu trouvé. Précisez votre recherche.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _message = 'Recherche indisponible (vérifiez la connexion).');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _pick(PlaceResult p) {
    _ctrl.text = p.name;
    setState(() {
      _selected = true;
      _results = [];
      _message = null;
    });
    widget.onChanged(p);
  }

  void _clear() {
    _ctrl.clear();
    setState(() {
      _selected = false;
      _results = [];
      _message = null;
    });
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _ctrl,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          onChanged: (_) {
            if (_selected) {
              setState(() => _selected = false);
              widget.onChanged(null); // texte modifié : le lieu doit être re-sélectionné
            }
          },
          decoration: InputDecoration(
            labelText: 'Lieu (optionnel)',
            hintText: 'Ex. : Bibliothèque, cafétéria…',
            prefixIcon: Icon(
              _selected ? Icons.check_circle_rounded : Icons.place_outlined,
              color: _selected ? t.success : null,
            ),
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_ctrl.text.isNotEmpty)
                      IconButton(icon: const Icon(Icons.close_rounded), onPressed: _clear),
                    IconButton(icon: const Icon(Icons.search_rounded), onPressed: _search),
                  ]),
          ),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_message!, style: text.bodySmall),
          ),
        if (_results.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: t.surface,
              border: Border.all(color: t.outline),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: _results
                  .map((p) => ListTile(
                        dense: true,
                        leading: Icon(Icons.place_rounded, size: 18, color: t.primary),
                        title: Text(p.name, style: text.bodyMedium!.copyWith(color: t.textPrimary)),
                        onTap: () => _pick(p),
                      ))
                  .toList(),
            ),
          ),
      ],
    );
  }
}