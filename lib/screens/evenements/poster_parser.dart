import 'event_validators.dart';
import 'poster_ocr.dart';

/// Ce que les règles ont trouvé sur l'affiche. Un champ null (ou faux) n'a
/// PAS été trouvé : rien n'est jamais inventé.
class PosterDraft {
  final String? title;
  final String? description;
  final DateTime? start;
  final DateTime? end;

  /// Date lue SANS heure : le début n'est pas rempli, l'utilisateur choisit
  /// l'heure lui-même (on n'invente pas d'heure).
  final DateTime? dateWithoutTime;
  final String? place;
  final double? priceTnd;
  final bool isFree;
  final List<String> warnings;

  /// Le texte lu est surtout dans un autre alphabet (arabe…), ignoré.
  final bool mostlyNonLatin;

  const PosterDraft({
    this.title,
    this.description,
    this.start,
    this.end,
    this.dateWithoutTime,
    this.place,
    this.priceTnd,
    this.isFree = false,
    this.warnings = const [],
    this.mostlyNonLatin = false,
  });

  bool get titleFound => title != null;
  bool get descriptionFound => description != null;
  bool get startFound => start != null;
  bool get endFound => end != null;
  bool get placeFound => place != null;
  bool get priceFound => isFree || priceTnd != null;

  /// Aucun champ trouvé (les avertissements ne comptent pas).
  bool get isEmpty =>
      !titleFound && !descriptionFound && !startFound && !endFound && dateWithoutTime == null && !placeFound && !priceFound;

  @override
  String toString() => 'PosterDraft(title: $title, start: $start, end: $end, dateWithoutTime: $dateWithoutTime, '
      'place: $place, price: $priceTnd, free: $isFree, description: $description, warnings: $warnings)';
}

/// Règles PURES (aucune dépendance Flutter, aucun réseau) qui transforment
/// les lignes lues sur une affiche en champs du formulaire.
///
/// Comparaisons sans accents ni majuscules ; le texte affiché reste l'original.
class PosterParser {
  PosterParser._();

  static const String latinOnlyWarning = 'Seul le texte en caractères latins est lu.';

  /// Une ligne voisine rejoint le titre si sa hauteur atteint ce ratio de
  /// celle de la ligne la plus grande.
  static const double titleMinRatio = 0.6;

  /// Suite du lieu sur la ligne suivante : 4 mots au plus, et (hors même
  /// paragraphe) un écart ≤ 0,6 × la hauteur de la ligne du lieu.
  static const int placeContinuationMaxWords = 4;
  static const double placeContinuationMaxGap = 0.6;

  /// Sigles gardés en majuscules quand un titre tout en capitales est converti.
  static const Set<String> acronyms = {
    'ESPRIT', 'PFE', 'IA', 'AI', 'CV', 'IEEE', 'ACM', 'GDG', 'BDE', 'RH', 'IT', 'UX', 'UI', 'IOT', 'TN', //
    'ENIT', 'INSAT', 'IHEC', 'ESSEC', 'ISET', 'DJ', 'QR', 'CTF', 'ONG', 'ONU', 'NASA', 'MIT', 'API', 'JCI',
  };

  static const List<String> _dayNames = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
  static const List<String> _monthNames = [
    'janvier', 'février', 'mars', 'avril', 'mai', 'juin', //
    'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
  ];

  // ------------------------------------------------------------- Formats

  /// « samedi 12 décembre 2026 ».
  static String formatDay(DateTime d) => '${_dayNames[d.weekday - 1]} ${d.day} ${_monthNames[d.month - 1]} ${d.year}';

  /// « samedi 12 décembre 2026 à 14:00 ».
  static String formatDateTime(DateTime d) =>
      '${formatDay(d)} à ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  // ------------------------------------------------- Normalisation du texte

  static const Map<String, String> _accents = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', //
    'ç': 'c',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
    'ñ': 'n',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
    'ý': 'y', 'ÿ': 'y',
    '’': "'", '‘': "'", '`': "'", '´': "'",
    '–': '-', '—': '-', '‑': '-', '−': '-',
    '\u00A0': ' ', '\u202F': ' ', '\t': ' ',
  };

  /// Minuscules sans accents, caractère par caractère : la chaîne garde la
  /// MÊME longueur que l'original, donc une position trouvée ici désigne le
  /// même passage dans le texte original.
  static String fold(String text) {
    final out = StringBuffer();
    for (final unit in text.codeUnits) {
      final ch = String.fromCharCode(unit);
      final lower = ch.toLowerCase();
      final one = lower.length == 1 ? lower : ch;
      out.write(_accents[one] ?? one);
    }
    return out.toString();
  }

  static const String _months = 'janvier|january|janv|jan|fevrier|february|fevr|fev|feb|mars|march|avril|april|avr'
      '|mai|may|juin|june|juillet|july|juil|aout|august|septembre|september|sept|sep|octobre|october|oct'
      '|novembre|november|nov|decembre|december|dec';
  static const String _days = 'lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche';

  static const Map<String, int> _monthNumber = {
    'janvier': 1, 'january': 1, 'janv': 1, 'jan': 1, //
    'fevrier': 2, 'february': 2, 'fevr': 2, 'fev': 2, 'feb': 2,
    'mars': 3, 'march': 3,
    'avril': 4, 'april': 4, 'avr': 4,
    'mai': 5, 'may': 5,
    'juin': 6, 'june': 6,
    'juillet': 7, 'july': 7, 'juil': 7,
    'aout': 8, 'august': 8,
    'septembre': 9, 'september': 9, 'sept': 9, 'sep': 9,
    'octobre': 10, 'october': 10, 'oct': 10,
    'novembre': 11, 'november': 11, 'nov': 11,
    'decembre': 12, 'december': 12, 'dec': 12,
  };

  // Bruit de lecture : O/o → 0 et l/I/| → 1, SEULEMENT dans un jeton qui a
  // déjà la forme d'une date ou d'une heure (et contient au moins un chiffre).
  static const String _d = '[0-9oil|]';
  static final RegExp _noisyNumericDate =
      RegExp('(?<![a-z0-9])($_d{1,2})([/.\\-])($_d{1,2})(?:\\2($_d{2,4}))?(?![a-z0-9])');
  static final RegExp _noisyDayBeforeMonth =
      RegExp('(?<![a-z0-9])($_d{1,2})(?=(?:er)?\\s*(?:$_months)(?![a-z]))');
  static final RegExp _noisyYearAfterMonth = RegExp('(?<=(?:$_months)\\.?\\s{1,3})($_d{4})(?![a-z0-9])');
  static final RegExp _noisyTimeH = RegExp('(?<![a-z0-9])($_d{1,2})(\\s*h\\s*)($_d{2})?(?![a-z0-9])');
  static final RegExp _noisyTimeColon = RegExp('(?<![a-z0-9])($_d{1,2}):($_d{2})(?![a-z0-9])');
  static final RegExp _digit = RegExp('[0-9]');

  static String _digits(String s) => s.replaceAll('o', '0').replaceAll(RegExp('[il|]'), '1');

  /// Corrige O/o/l/I/| dans les jetons en forme de date ou d'heure. Longueur
  /// conservée. Les groupes sans aucun vrai chiffre ne sont pas touchés.
  static String fixOcrDigits(String folded) {
    var f = folded;
    f = f.replaceAllMapped(_noisyNumericDate, (m) => _fix(m, [1, 3, 4]));
    f = f.replaceAllMapped(_noisyDayBeforeMonth, (m) => _fix(m, [1]));
    f = f.replaceAllMapped(_noisyYearAfterMonth, (m) => _fix(m, [1]));
    f = f.replaceAllMapped(_noisyTimeH, (m) {
      // L'heure doit contenir un chiffre ; des minutes sans chiffre ne sont
      // acceptées que sous la forme « OO » (14hOO), pas « 1 hil… ».
      final minutes = m[3];
      if (!_digit.hasMatch(m[1]!)) return m[0]!;
      if (minutes != null && !_digit.hasMatch(minutes) && minutes != 'oo') return m[0]!;
      return _digits(m[1]!) + m[2]! + (minutes == null ? '' : _digits(minutes));
    });
    f = f.replaceAllMapped(_noisyTimeColon, (m) => _fix(m, [1, 2]));
    return f;
  }

  /// Remplace les caractères ambigus aux seules positions des [groups] de [m],
  /// si chacun de ces groupes contient déjà au moins un vrai chiffre.
  static String _fix(Match m, List<int> groups) {
    final whole = m[0]!;
    for (final g in groups) {
      final v = m[g];
      if (v != null && !_digit.hasMatch(v)) return whole;
    }
    // Remplace les caractères ambigus seulement aux positions des groupes.
    final chars = whole.split('');
    var searchFrom = 0;
    for (final g in groups) {
      final v = m[g];
      if (v == null) continue;
      final at = whole.indexOf(v, searchFrom);
      for (var i = 0; i < v.length; i++) {
        chars[at + i] = _digits(chars[at + i]);
      }
      searchFrom = at + v.length;
    }
    return chars.join();
  }

  // ------------------------------------------------------------ Motifs

  static final RegExp _textDate = RegExp(
      '(?<![0-9a-z])(\\d{1,2})(?:er)?\\s*($_months)(?![a-z])\\.?(?:,?\\s+(\\d{4})(?![0-9]))?');
  static final RegExp _numericDate =
      RegExp('(?<![0-9a-z/.\\-:,])(\\d{1,2})([/.\\-])(\\d{1,2})(?:\\2(\\d{4}|\\d{2}))?(?![0-9a-z]|[/.\\-:]\\d)');
  static final RegExp _partialRangeDay = RegExp(
      '(?<![0-9a-z/.,])(\\d{1,2})(?:er)?\\s*(?:au|-|et|a)\\s*(?=\\d{1,2}(?:er)?\\s*(?:$_months)(?![a-z]))');
  static final RegExp _dateConnector = RegExp(r"^\s*(?:au|-|et|a|jusqu'au)\s*(?:(?:lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)\s+)?$");
  static final RegExp _weekdayBefore = RegExp('($_days)\\s*,?\\s*(?:le\\s+)?\$');

  static final RegExp _timeH = RegExp(r'(?<![0-9a-z:/.,])(\d{1,2})\s*h(?:eures?)?\s*(\d{2})?(?![0-9a-z])');
  static final RegExp _timeColon = RegExp(r'(?<![0-9a-z:/.,])(\d{1,2}):(\d{2})(?![0-9]|:\d)');
  static final RegExp _timeConnector = RegExp(r"^\s*(?:a|-|au|jusqu'a|jusqu'au|to)\s*$");

  static final RegExp _deadline = RegExp('(?<![a-z\\-])(?:avant(?![a-z\\-])\\s+(?:le\\s|l\'|\\d|(?:$_days)(?![a-z]))'
      '|date\\s+limite|cloture|delais?(?![a-z])|inscriptions?(?![a-z]))');
  static final RegExp _until = RegExp("jusqu'?\\s*(?:au|a)\\s+(?:le\\s+)?(?:(?:$_days)\\s+)?\\d{1,2}(?:er)?\\s*"
      '(?:[/.\\-]\\s*\\d|(?:$_months)(?![a-z]))');
  static final RegExp _rangeStart = RegExp('(?<![a-z])du\\s+(?:(?:$_days)\\s+)?\\d');

  static final RegExp _free = RegExp(r'(?<![a-z])(?:gratuit(?:e|s|es)?|entree\s+libre|acces\s+libre|free)(?![a-z])');
  static final RegExp _amount =
      RegExp(r'(?<![0-9a-z.,/])(\d{1,4}(?:[.,]\d{1,2})?)\s*(?:dt|tnd|dinars?|d\.t\.?)(?![a-z])');
  static final RegExp _labelledPrice =
      RegExp(r'(?<![a-z])(?:prix|tarif|entree|participation|frais)\s*:?\s*(\d{1,4}(?:[.,]\d{1,2})?)(?![0-9.,/:h])');

  static final RegExp _placeLabel = RegExp(r'^\s*(?:lieu(?![a-z])\s*:?|adresse\s*:|ou\s*:)\s*');
  static final RegExp _placeKeyword = RegExp(
      r'^\s*(?:salle|amphi|amphitheatre|bloc|campus|stade|hall|cour|bibliotheque|auditorium|terrain)(?![a-z])');

  static final RegExp _connectors = RegExp(
      '(?<![a-z])(?:du|au|aux|de|des|le|la|les|l|d|a|et|$_days|lieu|adresse|ou|prix|tarif|entree|participation'
      '|frais|date|dates|heure|heures|horaire|horaires|partir|from|to|at|on)(?![a-z])');
  static final RegExp _letterAz = RegExp('[a-z]');
  static final RegExp _anyLetter = RegExp(r'\p{L}', unicode: true);
  static final RegExp _latinLetter = RegExp(r'[A-Za-z\u00C0-\u024F]');
  static final RegExp _spaces = RegExp(r'[ \t\u00A0\u202F]+');

  // --------------------------------------------------------------- Analyse

  static PosterDraft parse(PosterOcrResult ocr, DateTime now) {
    final warnings = <String>[];

    // 1. Texte non latin : ignoré (pas une erreur), signalé s'il domine.
    var latin = 0, other = 0;
    final kept = <PosterOcrLine>[];
    for (final l in ocr.lines) {
      final letters = _anyLetter.allMatches(l.text).length;
      final latinCount = _latinLetter.allMatches(l.text).length;
      latin += latinCount;
      other += letters - latinCount;
      if (l.text.trim().isEmpty) continue;
      if (letters - latinCount > latinCount) continue; // ligne surtout non latine
      kept.add(l);
    }
    final mostlyNonLatin = other > latin;
    if (mostlyNonLatin) warnings.add(latinOnlyWarning);

    final lines = [for (var i = 0; i < kept.length; i++) _Line(i, kept[i])];
    if (lines.isEmpty) return PosterDraft(warnings: warnings, mostlyNonLatin: mostlyNonLatin);

    final today = DateTime(now.year, now.month, now.day);
    for (final l in lines) {
      l.analyse(today);
    }

    // 2. Date et heure.
    DateTime? start, end, dateOnly;
    final candidates = [
      for (final l in lines)
        if (!l.deadline)
          for (final c in l.dates) (line: l, date: c),
    ];
    if (candidates.isNotEmpty) {
      candidates.sort((a, b) {
        final t = (b.line.times.isNotEmpty ? 1 : 0) - (a.line.times.isNotEmpty ? 1 : 0);
        if (t != 0) return t;
        final h = b.line.ocr.height.compareTo(a.line.ocr.height);
        if (h != 0) return h;
        return a.date.start.compareTo(b.date.start);
      });
      final chosen = candidates.first;
      warnings.addAll(chosen.date.warnings);
      final timeLine = chosen.line.times.isNotEmpty ? chosen.line : _nearestTimeLine(lines, chosen.line.index);
      final first = chosen.date.start;
      final last = chosen.date.end ?? first;
      if (timeLine == null) {
        if (first.isBefore(today)) {
          warnings.add('Date détectée dans le passé : ${formatDay(first)}.');
        } else {
          dateOnly = first;
          warnings.add('Date lue sans heure : ${formatDay(first)}. Choisissez l\'heure avec « Début ».');
        }
      } else {
        final t = timeLine.times;
        final range = timeLine.timeRange;
        final startTime = t.first;
        var s = DateTime(first.year, first.month, first.day, startTime.$1, startTime.$2);
        DateTime? e;
        if (range != null) {
          e = DateTime(last.year, last.month, last.day, range.$1, range.$2);
          // Une seule journée « 22h à 2h » : la fin est le lendemain.
          if (chosen.date.end == null && !e.isAfter(s)) e = e.add(const Duration(days: 1));
        }
        final startError = EventValidators.start(s, now: now);
        if (startError != null) {
          if (s.isBefore(now)) {
            warnings.add('Date détectée dans le passé : ${formatDateTime(s)}.');
          } else if (s.isBefore(now.add(EventValidators.minLeadTime))) {
            warnings.add('Date détectée trop proche (moins de 15 minutes) : ${formatDateTime(s)}.');
          } else {
            warnings.add('Date détectée à plus d\'un an : ${formatDateTime(s)}.');
          }
        } else {
          start = s;
          if (e != null) {
            if (EventValidators.end(s, e) == null) {
              end = e;
            } else {
              warnings.add('Fin lue (${formatDateTime(e)}) incompatible avec le début : choisissez-la à la main.');
            }
          }
        }
      }
    } else if (lines.any((l) => !l.deadline && l.times.isNotEmpty)) {
      warnings.add('Heure lue sans date : choisissez la date avec « Début ».');
    }

    // 3. Prix (toutes les lignes hors date limite).
    double? price;
    var isFree = false;
    for (final l in lines) {
      if (l.deadline) continue;
      if (price == null && l.price != null) price = l.price;
      if (l.free) isFree = true;
    }
    if (price == 0) {
      price = null;
      isFree = true;
    }
    if (price != null && isFree) {
      warnings.add('Un prix et « gratuit » sont écrits : vérifiez le prix.');
      isFree = false;
    }

    // 4. Lieu : d'abord une ligne étiquetée « Lieu : », sinon une ligne qui
    //    commence par salle, amphi, bloc… (pas la plus grande : ce serait le titre).
    final placeLines = <int>{};
    String? place;
    var placeRaw = ''; // texte brut du lieu (virgule finale gardée pour la suite)
    final maxHeight = lines.map((l) => l.ocr.height).reduce((a, b) => a > b ? a : b);
    for (final l in lines) {
      final m = _placeLabel.firstMatch(l.f);
      if (m == null || l.deadline) continue;
      placeRaw = l.text.substring(m.end);
      var text = _clean(placeRaw);
      placeLines.add(l.index);
      if (text.isEmpty && l.index + 1 < lines.length) {
        placeLines.add(l.index + 1);
        placeRaw = lines[l.index + 1].text;
        text = _clean(placeRaw);
      }
      place = _fitPlace(text);
      if (place != null) break;
    }
    if (place == null) {
      for (final l in lines) {
        if (l.deadline || !_placeKeyword.hasMatch(l.f) || l.ocr.height >= maxHeight) continue;
        placeRaw = l.text;
        place = _fitPlace(_clean(l.text));
        if (place != null) {
          placeLines.add(l.index);
          break;
        }
      }
    }
    for (final i in placeLines) {
      lines[i].place = true;
    }

    // 5. Titre : la plus grande ligne « libre » (l'ancre), étendue vers le haut
    //    et vers le bas dans l'ordre de lecture tant que la ligne voisine est
    //    libre, assez grande (≥ 60 % de l'ancre : une majuscule accentuée
    //    agrandit le cadre d'une ligne, pas d'une autre) et proche (même
    //    paragraphe, ou écart ≤ la hauteur de la plus grande des deux lignes).
    //    Un nombre seul (« 2026 » sur sa propre ligne) peut compléter le titre.
    final titleLines = <int>{};
    String? title;
    final free = [for (final l in lines) if (l.isTitleCandidate) l];
    if (free.isNotEmpty) {
      var anchor = free.first;
      for (final l in free) {
        if (l.ocr.height > anchor.ocr.height) anchor = l;
      }
      // Un nombre seul n'est pas candidat : on le borne aussi par le haut
      // (une grande date décorative n'entre pas dans un titre plus petit).
      bool joins(_Line l) =>
          (l.isTitleCandidate || (l.isLoneNumber && l.ocr.height <= 1.2 * anchor.ocr.height)) &&
          l.ocr.height >= titleMinRatio * anchor.ocr.height;
      bool close(_Line a, _Line b) =>
          a.ocr.block == b.ocr.block || b.ocr.top - a.ocr.bottom <= (a.ocr.height > b.ocr.height ? a.ocr.height : b.ocr.height);
      var from = anchor.index, to = anchor.index;
      while (from - 1 >= 0 && joins(lines[from - 1]) && close(lines[from - 1], lines[from])) {
        from--;
      }
      while (to + 1 < lines.length && joins(lines[to + 1]) && close(lines[to], lines[to + 1])) {
        to++;
      }
      final raw = _clean([for (var i = from; i <= to; i++) lines[i].text].join(' '));
      final cased = isMostlyUpperCase(raw) ? sentenceCase(raw) : raw;
      final fitted = truncateAtWord(cased, EventValidators.titleMax);
      if (EventValidators.title(fitted) == null) {
        title = fitted;
        for (var i = from; i <= to; i++) {
          titleLines.add(i);
        }
      }
    }

    // 5b. Suite du lieu : « Lieu : Hall principal, campus » puis « ESPRIT ».
    //     Une ligne suivante est ajoutée si elle est dans le même paragraphe,
    //     ou de hauteur voisine (± 20 %) et très proche (écart ≤ 0,6 × la
    //     hauteur de ligne) ; libre (ni date, ni prix…, ni titre) ; courte
    //     (4 mots au plus) ; et si le lieu complet reste dans la limite.
    if (place != null && placeLines.isNotEmpty) {
      var last = lines[placeLines.reduce((a, b) => a > b ? a : b)];
      var text = place;
      var raw = placeRaw;
      for (var q = last.index + 1; q < lines.length; q++) {
        final next = lines[q];
        if (titleLines.contains(q) || next.classified || !(next.hasWords || next.isLoneNumber)) break;
        if (next.text.trim().split(RegExp(r'\s+')).length > placeContinuationMaxWords) break;
        final sameBlock = next.ocr.block == last.ocr.block;
        final similar = (next.ocr.height - last.ocr.height).abs() <= 0.2 * last.ocr.height;
        final tight = next.ocr.top - last.ocr.bottom <= placeContinuationMaxGap * last.ocr.height;
        if (!sameBlock && !(similar && tight)) break;
        final combined = _clean('$raw ${next.text}');
        if (EventValidators.location(combined) != null) break;
        text = combined;
        raw = '$raw ${next.text}';
        next.place = true;
        last = next;
      }
      place = text;
    }

    // 6. Description : les autres lignes avec du texte, sauf petites lignes et
    //    bandeaux / pieds de page (10 % du haut et du bas du texte). La
    //    médiane des hauteurs ignore les lignes du titre (un titre sur 5 lignes
    //    la tirerait vers le haut et ferait passer le texte courant pour petit).
    final bodyLines = [for (final l in lines) if (!titleLines.contains(l.index)) l];
    final heights = [for (final l in bodyLines.isEmpty ? lines : bodyLines) l.ocr.height]..sort();
    final median = heights.length.isOdd
        ? heights[heights.length ~/ 2]
        : (heights[heights.length ~/ 2 - 1] + heights[heights.length ~/ 2]) / 2;
    final minTop = lines.map((l) => l.ocr.top).reduce((a, b) => a < b ? a : b);
    final maxBottom = lines.map((l) => l.ocr.bottom).reduce((a, b) => a > b ? a : b);
    final band = (maxBottom - minTop) * 0.10;
    final useBands = lines.length >= 3 && band > 0;
    final described = <String>[];
    for (final l in lines) {
      if (titleLines.contains(l.index) || l.place || l.deadline || l.pureInfo || !l.hasWords) continue;
      if (l.ocr.height < 0.6 * median) continue;
      if (useBands && (l.ocr.center < minTop + band || l.ocr.center > maxBottom - band)) continue;
      described.add(_clean(l.text));
    }
    String? description;
    if (described.isNotEmpty) {
      final text = truncateAtWord(described.join('\n'), EventValidators.descriptionMax);
      if (EventValidators.description(text) == null) description = text;
    }

    return PosterDraft(
      title: title,
      description: description,
      start: start,
      end: end,
      dateWithoutTime: dateOnly,
      place: place,
      priceTnd: price,
      isFree: isFree,
      warnings: warnings,
      mostlyNonLatin: mostlyNonLatin,
    );
  }

  /// Ligne la plus proche (sans date, hors date limite) qui porte une heure.
  static _Line? _nearestTimeLine(List<_Line> lines, int from) {
    _Line? best;
    for (final l in lines) {
      if (l.deadline || l.times.isEmpty || l.dates.isNotEmpty) continue;
      final d = (l.index - from).abs();
      final bestD = best == null ? 1 << 30 : (best.index - from).abs();
      if (d < bestD || (d == bestD && l.index > from)) best = l;
    }
    return best;
  }

  /// Compte rendu lisible (lignes lues puis champs trouvés) pour le journal de
  /// débogage. Chaque ligne commence par « [PosterScan] ».
  static List<String> debugReport(PosterOcrResult ocr, PosterDraft d) {
    String n(double v) => v.toStringAsFixed(0);
    final out = <String>['[PosterScan] ${ocr.lines.length} ligne(s) lue(s)'];
    for (var i = 0; i < ocr.lines.length; i++) {
      final l = ocr.lines[i];
      final gap = i == 0 ? '-' : n(l.top - ocr.lines[i - 1].bottom);
      out.add('[PosterScan] #$i bloc=${l.block} top=${n(l.top)} h=${n(l.height)} écart=$gap « ${l.text} »');
    }
    String f(String name, bool found, Object? value) => '[PosterScan] $name: ${found ? 'trouvé' : 'non trouvé'}'
        '${found ? ' → $value' : ''}';
    out
      ..add(f('titre', d.titleFound, d.title))
      ..add(f('début', d.startFound, d.start))
      ..add(f('fin', d.endFound, d.end))
      ..add(f('date sans heure', d.dateWithoutTime != null, d.dateWithoutTime))
      ..add(f('lieu', d.placeFound, d.place))
      ..add(f('prix', d.priceFound, d.isFree ? 'gratuit' : d.priceTnd))
      ..add(f('description', d.descriptionFound, d.description?.replaceAll('\n', ' ⏎ ')));
    for (final w in d.warnings) {
      out.add('[PosterScan] avertissement: $w');
    }
    return out;
  }

  static String _clean(String s) =>
      s.replaceAll(_spaces, ' ').trim().replaceAll(RegExp(r'^[\s:·,\-–]+|[\s:·,\-–]+$'), '').trim();

  static String? _fitPlace(String text) {
    final fitted = truncateAtWord(text, EventValidators.locationMax);
    return EventValidators.location(fitted) == null ? fitted : null;
  }

  // ------------------------------------------------------- Mise en forme

  /// Au moins 80 % des lettres en majuscules (et au moins 3 lettres).
  static bool isMostlyUpperCase(String s) {
    final letters = _anyLetter.allMatches(s).map((m) => m[0]!).toList();
    if (letters.length < 3) return false;
    final upper = letters.where((c) => c != c.toLowerCase() && c == c.toUpperCase()).length;
    return upper / letters.length >= 0.8;
  }

  /// « TOURNOI DE FOOTBALL » → « Tournoi de football ». Les sigles connus
  /// (ESPRIT, PFE…) et les mots avec des chiffres restent tels quels.
  static String sentenceCase(String s) {
    final words = s.split(' ').map((token) {
      if (_digit.hasMatch(token)) return token;
      return token.splitMapJoin(
        RegExp(r'\p{L}+', unicode: true),
        onMatch: (m) {
          final w = m[0]!;
          return acronyms.contains(w.toUpperCase()) && w == w.toUpperCase() ? w : w.toLowerCase();
        },
        onNonMatch: (n) => n,
      );
    }).join(' ');
    final first = _anyLetter.firstMatch(words);
    if (first == null) return words;
    return words.substring(0, first.start) + words[first.start].toUpperCase() + words.substring(first.start + 1);
  }

  /// Coupe à [max] caractères au plus, sur une fin de mot.
  static String truncateAtWord(String s, int max) {
    if (s.length <= max) return s;
    var cut = -1;
    for (var i = max; i > 0; i--) {
      if (s[i] == ' ' || s[i] == '\n') {
        cut = i;
        break;
      }
    }
    final r = cut > 0 ? s.substring(0, cut) : s.substring(0, max);
    return r.replaceAll(RegExp(r'[\s,;:·\-–]+$'), '');
  }

  // ---------------------------------------------------- Dates (internes)

  static bool _valid(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return false;
    final date = DateTime(y, m, d);
    return date.year == y && date.month == m && date.day == d;
  }

  static int _year(String? y) => y == null ? -1 : (y.length == 2 ? 2000 + int.parse(y) : int.parse(y));
}

/// Une date lue (éventuellement une plage) et ses avertissements.
class _DateHit {
  final DateTime start;
  final DateTime? end;
  final List<String> warnings;
  const _DateHit(this.start, this.end, this.warnings);
}

/// Date brute avant résolution de l'année.
class _Raw {
  final int start, end; // positions dans le texte
  final int day, month;
  final int year; // -1 = absente
  _Raw(this.start, this.end, this.day, this.month, this.year);
}

class _Line {
  final int index;
  final PosterOcrLine ocr;
  final String text;
  late final String f;
  final List<_DateHit> dates = [];
  final List<(int, int)> times = [];
  (int, int)? timeRange;
  bool deadline = false;
  bool free = false;
  double? price;
  bool place = false;
  bool pureInfo = false;
  bool hasWords = false;
  bool hasPriceOrLabel = false;

  _Line(this.index, this.ocr) : text = ocr.text {
    f = PosterParser.fixOcrDigits(PosterParser.fold(text));
  }

  /// La ligne porte une information reconnue (date, heure, lieu, prix…).
  bool get classified =>
      place || deadline || dates.isNotEmpty || times.isNotEmpty || free || price != null || hasPriceOrLabel;

  bool get isTitleCandidate => !classified && hasWords;

  /// « 2026 » seul sur sa ligne : une année seule n'est jamais une date.
  bool get isLoneNumber => !classified && RegExp(r'^\d{1,4}$').hasMatch(text.trim());

  void analyse(DateTime today) {
    final blank = List<bool>.filled(f.length, false);
    void mark(int s, int e) {
      for (var i = s; i < e && i < blank.length; i++) {
        blank[i] = true;
      }
    }

    deadline = PosterParser._deadline.hasMatch(f) ||
        (PosterParser._until.hasMatch(f) && !PosterParser._rangeStart.hasMatch(f));

    // --- Dates
    final raws = <_Raw>[];
    for (final m in PosterParser._textDate.allMatches(f)) {
      raws.add(_Raw(m.start, m.end, int.parse(m[1]!), PosterParser._monthNumber[m[2]!]!, PosterParser._year(m[3])));
    }
    for (final m in PosterParser._numericDate.allMatches(f)) {
      final sep = m[2]!;
      if (sep != '/' && m[4] == null) continue; // « 12.12 » ou « 10-12 » sans année : trop ambigu
      raws.add(_Raw(m.start, m.end, int.parse(m[1]!), int.parse(m[3]!), PosterParser._year(m[4])));
    }
    raws.sort((a, b) => a.start.compareTo(b.start));
    for (final r in raws) {
      mark(r.start, r.end);
    }

    // Plages « 8 - 9 décembre », « 8 et 9 décembre », « du 8 au 9 décembre ».
    final partials = <int, _Raw>{}; // position de la date complète → jour de début
    for (final m in PosterParser._partialRangeDay.allMatches(f)) {
      partials[m.end] = _Raw(m.start, m.end, int.parse(m[1]!), 0, -1);
      mark(m.start, m.end);
    }
    final used = <int>{};
    for (var i = 0; i < raws.length; i++) {
      if (used.contains(i)) continue;
      final r = raws[i];
      final weekday = _weekdayBefore(partials[r.start]?.start ?? r.start);
      final partial = partials[r.start];
      if (partial != null) {
        _addRange(_Raw(partial.start, partial.end, partial.day, r.month, r.year), r, weekday, today);
        used.add(i);
        continue;
      }
      if (i + 1 < raws.length && PosterParser._dateConnector.hasMatch(f.substring(r.end, raws[i + 1].start))) {
        _addRange(r, raws[i + 1], weekday, today);
        used.addAll([i, i + 1]);
        continue;
      }
      final single = _resolve(r.day, r.month, r.year, weekday, today);
      if (single != null) dates.add(_DateHit(single.$1, null, single.$2));
      used.add(i);
    }

    // --- Heures (hors zones de date)
    final found = <(int, int, int, int)>[]; // début, fin, heure, minute
    void addTime(Match m, int h, int min) {
      if (blank[m.start]) return;
      found.add((m.start, m.end, h, min));
      mark(m.start, m.end);
    }

    for (final m in PosterParser._timeH.allMatches(f)) {
      final h = int.parse(m[1]!);
      final min = m[2] == null ? 0 : int.parse(m[2]!);
      if (h <= 23 && min <= 59) addTime(m, h, min);
    }
    for (final m in PosterParser._timeColon.allMatches(f)) {
      final h = int.parse(m[1]!);
      final min = int.parse(m[2]!);
      if (h <= 23 && min <= 59) addTime(m, h, min);
    }
    found.sort((a, b) => a.$1.compareTo(b.$1));
    for (final t in found) {
      times.add((t.$3, t.$4));
    }
    if (found.length >= 2 && PosterParser._timeConnector.hasMatch(f.substring(found[0].$2, found[1].$1))) {
      timeRange = (found[1].$3, found[1].$4);
    }

    // --- Prix
    if (PosterParser._free.hasMatch(f)) free = true;
    for (final m in PosterParser._free.allMatches(f)) {
      mark(m.start, m.end);
    }
    for (final re in [PosterParser._amount, PosterParser._labelledPrice]) {
      for (final m in re.allMatches(f)) {
        if (blank[m.start]) continue;
        final value = m[1]!.replaceAll(',', '.');
        if (EventValidators.price(value) == null) price ??= double.parse(value);
        hasPriceOrLabel = true;
        mark(m.start, m.end);
      }
    }
    final label = PosterParser._placeLabel.firstMatch(f);
    if (label != null) mark(label.start, label.end);

    // --- Reste-t-il du vrai texte une fois les infos retirées ?
    final rest = StringBuffer();
    for (var i = 0; i < f.length; i++) {
      rest.write(blank[i] ? ' ' : f[i]);
    }
    final leftover = rest.toString().replaceAll(PosterParser._connectors, ' ');
    final letters = PosterParser._letterAz.allMatches(leftover).length;
    final hasInfo = dates.isNotEmpty || times.isNotEmpty || free || hasPriceOrLabel || label != null || raws.isNotEmpty;
    pureInfo = hasInfo && letters <= 3;
    hasWords = text.trim().length >= 3 && PosterParser._letterAz.allMatches(f).length >= 2;
  }

  /// Jour de la semaine écrit juste avant la position [pos] (« Samedi 12 »).
  int? _weekdayBefore(int pos) {
    final m = PosterParser._weekdayBefore.firstMatch(f.substring(0, pos));
    if (m == null) return null;
    return const ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'].indexOf(m[1]!) + 1;
  }

  void _addRange(_Raw a, _Raw b, int? weekday, DateTime today) {
    var ay = a.year, by = b.year;
    final warnings = <String>[];
    DateTime? s;
    if (ay < 0 && by < 0) {
      final r = _resolve(a.day, a.month, -1, weekday, today);
      if (r == null) return;
      s = r.$1;
      warnings.addAll(r.$2);
      ay = s.year;
      by = ay;
      if (PosterParser._valid(by, b.month, b.day) && DateTime(by, b.month, b.day).isBefore(s)) by++;
    } else {
      if (ay < 0) {
        ay = by;
        if (PosterParser._valid(ay, a.month, a.day) &&
            PosterParser._valid(by, b.month, b.day) &&
            DateTime(ay, a.month, a.day).isAfter(DateTime(by, b.month, b.day))) {
          ay--;
        }
      }
      if (by < 0) {
        by = ay;
        if (PosterParser._valid(by, b.month, b.day) && DateTime(by, b.month, b.day).isBefore(DateTime(ay, a.month, a.day))) {
          by++;
        }
      }
      final r = _resolve(a.day, a.month, ay, weekday, today);
      if (r == null) return;
      s = r.$1;
      warnings.addAll(r.$2);
    }
    if (!PosterParser._valid(by, b.month, b.day)) return;
    final e = DateTime(by, b.month, b.day);
    if (e.isBefore(s)) return;
    dates.add(_DateHit(s, e, warnings));
  }

  /// Année absente : prochaine occurrence non passée, en préférant l'année où
  /// le jour de la semaine écrit correspond. Date impossible (31/02) : null.
  (DateTime, List<String>)? _resolve(int day, int month, int year, int? weekday, DateTime today) {
    final warnings = <String>[];
    DateTime date;
    if (year >= 0) {
      if (!PosterParser._valid(year, month, day)) return null;
      date = DateTime(year, month, day);
    } else {
      final options = [
        for (final y in [today.year, today.year + 1])
          if (PosterParser._valid(y, month, day) && !DateTime(y, month, day).isBefore(today)) DateTime(y, month, day),
      ];
      if (options.isEmpty) return null;
      date = options.first;
      if (weekday != null) {
        for (final o in options) {
          if (o.weekday == weekday) {
            date = o;
            break;
          }
        }
      }
    }
    if (weekday != null && date.weekday != weekday) {
      const names = PosterParser._dayNames;
      warnings.add('Le jour écrit (${names[weekday - 1]}) ne correspond pas au '
          '${date.day} ${PosterParser._monthNames[date.month - 1]} ${date.year}, qui est un ${names[date.weekday - 1]}.');
    }
    return (date, warnings);
  }
}
