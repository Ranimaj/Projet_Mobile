import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_tokens.dart';
import 'poster_parser.dart';

/// Feuille « Prendre une photo / Choisir dans la galerie / Annuler ».
/// Renvoie la source choisie, ou null si annulé.
Future<ImageSource?> showPosterSourceSheet(BuildContext context) {
  return showModalBottomSheet<ImageSource>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (ctx) => SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              minTileHeight: 56,
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              minTileHeight: 56,
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choisir dans la galerie'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              minTileHeight: 56,
              leading: const Icon(Icons.close_rounded),
              title: const Text('Annuler'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Champs que la lecture d'affiche peut remplir.
enum PosterField { title, start, end, place, price, description }

/// Une ligne de la feuille de vérification.
class PosterReviewRow {
  final PosterField field;
  final String label;

  /// Valeur lue, telle qu'affichée (« Non lu » si rien).
  final String value;

  /// Une case à cocher est proposée (valeur trouvée et applicable).
  final bool selectable;

  /// Le champ du formulaire a déjà une valeur saisie par l'utilisateur.
  final bool wouldReplace;

  const PosterReviewRow({
    required this.field,
    required this.label,
    required this.value,
    required this.selectable,
    this.wouldReplace = false,
  });

  /// Cochée au départ seulement si elle n'écrase rien.
  bool get initiallyChecked => selectable && !wouldReplace;
}

/// Ce que l'utilisateur a validé.
class PosterReviewChoice {
  final Set<PosterField> fields;
  final bool usePoster;
  const PosterReviewChoice(this.fields, {required this.usePoster});
}

/// État actuel du formulaire, pour savoir ce qu'un remplissage écraserait.
class PosterFormState {
  final bool titleFilled;
  final bool descriptionFilled;
  final bool placeFilled;
  final bool priceFilled;

  /// Début / fin choisis par l'utilisateur (sinon : valeurs par défaut).
  final bool startTouched;
  final bool endTouched;

  const PosterFormState({
    this.titleFilled = false,
    this.descriptionFilled = false,
    this.placeFilled = false,
    this.priceFilled = false,
    this.startTouched = false,
    this.endTouched = false,
  });
}

/// « 5 TND », « 12,50 TND » ou « Gratuit ».
String posterPriceLabel(PosterDraft d) {
  if (d.isFree) return 'Gratuit';
  final p = d.priceTnd!;
  final text = p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toStringAsFixed(2).replaceAll('.', ',');
  return '$text TND';
}

/// Lignes de la feuille de vérification (règle pure, testée à part).
/// La description n'est proposée que si celle du formulaire est vide.
List<PosterReviewRow> posterReviewRows(PosterDraft d, PosterFormState form) {
  const notRead = 'Non lu';
  return [
    PosterReviewRow(
      field: PosterField.title,
      label: 'Titre',
      value: d.title ?? notRead,
      selectable: d.titleFound,
      wouldReplace: d.titleFound && form.titleFilled,
    ),
    PosterReviewRow(
      field: PosterField.start,
      label: 'Début',
      value: d.start != null
          ? PosterParser.formatDateTime(d.start!)
          : (d.dateWithoutTime != null ? '${PosterParser.formatDay(d.dateWithoutTime!)} (heure non lue)' : notRead),
      selectable: d.startFound,
      wouldReplace: d.startFound && form.startTouched,
    ),
    PosterReviewRow(
      field: PosterField.end,
      label: 'Fin',
      value: d.end != null ? PosterParser.formatDateTime(d.end!) : notRead,
      selectable: d.endFound,
      wouldReplace: d.endFound && form.endTouched,
    ),
    PosterReviewRow(
      field: PosterField.place,
      label: 'Lieu',
      value: d.place ?? notRead,
      selectable: d.placeFound,
      wouldReplace: d.placeFound && form.placeFilled,
    ),
    PosterReviewRow(
      field: PosterField.price,
      label: 'Prix',
      value: d.priceFound ? posterPriceLabel(d) : notRead,
      selectable: d.priceFound,
      wouldReplace: d.priceFound && form.priceFilled,
    ),
    if (!form.descriptionFilled)
      PosterReviewRow(
        field: PosterField.description,
        label: 'Description',
        value: d.description ?? notRead,
        selectable: d.descriptionFound,
      ),
  ];
}

const String posterNothingReadMessage =
    'Aucune information reconnue. Essayez une photo plus nette et bien cadrée, avec du texte imprimé.';

/// Feuille « Voici ce que j'ai lu ». Renvoie le choix, ou null si annulé.
Future<PosterReviewChoice?> showPosterReviewSheet(
  BuildContext context, {
  required PosterDraft draft,
  required PosterFormState form,
  required bool hasPoster,
}) {
  return showModalBottomSheet<PosterReviewChoice>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => PosterReviewSheet(draft: draft, rows: posterReviewRows(draft, form), hasPoster: hasPoster),
  );
}

class PosterReviewSheet extends StatefulWidget {
  final PosterDraft draft;
  final List<PosterReviewRow> rows;

  /// Une affiche est déjà choisie : l'image lue la remplacerait.
  final bool hasPoster;

  const PosterReviewSheet({super.key, required this.draft, required this.rows, required this.hasPoster});

  @override
  State<PosterReviewSheet> createState() => _PosterReviewSheetState();
}

class _PosterReviewSheetState extends State<PosterReviewSheet> {
  late final Set<PosterField> _checked = {
    for (final r in widget.rows)
      if (r.initiallyChecked) r.field,
  };

  /// Par défaut oui, sauf si cela remplacerait une affiche déjà choisie.
  late bool _usePoster = !widget.hasPoster;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final theme = Theme.of(context);
    final empty = widget.draft.isEmpty;

    Widget note(IconData icon, Color color, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 18, color: color)),
              const SizedBox(width: 8),
              Expanded(child: Text(text)),
            ],
          ),
        );

    final warnings = [
      ...widget.draft.warnings,
      // Toujours rappelé quand rien n'a été lu.
      if (empty && !widget.draft.warnings.contains(PosterParser.latinOnlyWarning)) PosterParser.latinOnlyWarning,
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text("Voici ce que j'ai lu", style: theme.textTheme.titleLarge),
          ),
          const SizedBox(height: 8),
          if (empty)
            note(Icons.search_off_rounded, t.textSecondary, posterNothingReadMessage)
          else ...[
            Text('Cochez ce que vous voulez reprendre. Rien n\'est enregistré avant « Créer l\'événement ».',
                style: TextStyle(color: t.textSecondary)),
            const SizedBox(height: 4),
            for (final row in widget.rows) _row(row, t),
          ],
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final w in warnings) note(Icons.info_outline_rounded, t.warning, w),
          ],
          if (!empty)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _usePoster,
              onChanged: (v) => setState(() => _usePoster = v),
              title: const Text("Utiliser cette image comme affiche de l'événement"),
              subtitle: widget.hasPoster ? const Text("remplacerait l'affiche actuelle") : null,
            ),
          const SizedBox(height: 8),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: 8,
            overflowSpacing: 4,
            children: empty
                ? [
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Fermer'),
                    ),
                  ]
                : [
                    TextButton(
                      style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Annuler'),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
                      onPressed: _checked.isEmpty && !_usePoster
                          ? null
                          : () => Navigator.pop(context, PosterReviewChoice({..._checked}, usePoster: _usePoster)),
                      child: const Text('Appliquer'),
                    ),
                  ],
          ),
        ],
      ),
    );
  }

  Widget _row(PosterReviewRow row, AppTokens t) {
    final value = Text(
      row.value,
      maxLines: row.field == PosterField.description ? 4 : 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: row.selectable || row.field == PosterField.start ? null : t.textSecondary),
    );
    final subtitle = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        value,
        if (row.wouldReplace)
          Text('remplacerait la valeur actuelle', style: TextStyle(color: t.warning, fontSize: 12.5)),
      ],
    );
    if (!row.selectable) {
      // Rien à cocher : valeur absente, ou date sans heure (non remplie).
      return ListTile(
        contentPadding: EdgeInsets.zero,
        minTileHeight: 48,
        leading: const SizedBox(width: 48),
        title: Text(row.label),
        subtitle: subtitle,
      );
    }
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      value: _checked.contains(row.field),
      onChanged: (v) => setState(() => v == true ? _checked.add(row.field) : _checked.remove(row.field)),
      title: Text(row.label),
      subtitle: subtitle,
    );
  }
}
