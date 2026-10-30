import 'package:flutter/material.dart';
import '../core/theme/app_tokens.dart';
import '../services/translation_service.dart';

/// Texte avec bouton "Traduire" (français -> anglais / arabe).
class TranslatableText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  const TranslatableText({super.key, required this.text, this.style});

  @override
  State<TranslatableText> createState() => _TranslatableTextState();
}

class _TranslatableTextState extends State<TranslatableText> {
  final _service = TranslationService();
  String? _translated;
  String? _lang;
  bool _loading = false;
  String? _error;

  Future<void> _translate(String lang) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.translate(widget.text, to: lang);
      if (!mounted) return;
      setState(() {
        _translated = result;
        _lang = lang;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Traduction indisponible (vérifiez la connexion).');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void didUpdateWidget(covariant TranslatableText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _translated = null;
      _lang = null;
      _error = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final text = Theme.of(context).textTheme;
    final showing = _translated ?? widget.text;
    final isArabic = _translated != null && _lang == 'ar';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Directionality(
          textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
          child: SelectableText(showing, style: widget.style),
        ),
        const SizedBox(height: 10),
        Row(children: [
          if (_loading)
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          else if (_translated != null)
            TextButton.icon(
              onPressed: () => setState(() {
                _translated = null;
                _lang = null;
              }),
              icon: const Icon(Icons.undo_rounded, size: 16),
              label: const Text('Voir l’original'),
            )
          else
            PopupMenuButton<String>(
              onSelected: _translate,
              itemBuilder: (_) => TranslationService.languages.entries
                  .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.translate_rounded, size: 18, color: t.primary),
                  const SizedBox(width: 6),
                  Text('Traduire', style: text.labelLarge!.copyWith(color: t.primary)),
                ]),
              ),
            ),
        ]),
        if (_error != null) Text(_error!, style: text.bodySmall!.copyWith(color: t.danger)),
      ],
    );
  }
}
