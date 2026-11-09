import 'package:campusconnect/screens/evenements/poster_ocr.dart';
import 'package:campusconnect/screens/evenements/poster_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'poster_fixtures.dart';

/// Ligne de test : position automatique, hauteur « info » (28) par défaut.
PosterOcrLine _l(String text, {double top = 0, double height = 28}) =>
    PosterOcrLine(text, top: top, height: height);

/// Analyse des lignes empilées (12 px d'écart, un paragraphe par ligne),
/// « maintenant » = 9/11/2026 11:00.
PosterDraft _parse(List<Object> lines, {DateTime? now}) {
  var top = 0.0;
  final ocr = <PosterOcrLine>[];
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    final line = l is PosterOcrLine ? l : _l(l as String);
    ocr.add(PosterOcrLine(line.text, top: top, height: line.height, block: i));
    top += line.height + 12;
  }
  return PosterParser.parse(PosterOcrResult(ocr), now ?? posterNow);
}

/// Début lu sur une seule ligne d'infos.
DateTime? _start(String line, {DateTime? now}) => _parse(['Titre de test', line], now: now).start;

void main() {
  group('affiches de référence', () {
    for (final fx in posterFixtures) {
      test(fx.file, () {
        final d = PosterParser.parse(fx.ocr, posterNow);
        expect(d.title, fx.title);
        expect(d.start, fx.start);
        expect(d.end, fx.end);
        expect(d.place, fx.place);
        expect(d.priceTnd, fx.price);
        expect(d.isFree, fx.free);
        expect(d.description, fx.description);
      });
    }

    test('affiche 1 : bandeau et pied de page hors description', () {
      final d = PosterParser.parse(posterFixtures[0].ocr, posterNow);
      expect(d.description, isNot(contains('VIE DE CAMPUS')));
      expect(d.description, isNot(contains('Club Sport')));
    });

    test('affiche 5 : la date limite (10 décembre) est ignorée, année déduite', () {
      final d = PosterParser.parse(posterFixtures[4].ocr, posterNow);
      expect(d.start, DateTime(2026, 12, 15, 18));
      expect(d.warnings, isEmpty);
    });
  });

  group('mois', () {
    test('noms complets (avec et sans accent)', () {
      const names = [
        'janvier', 'février', 'mars', 'avril', 'mai', 'juin', //
        'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
      ];
      // Novembre 2026 → octobre 2027 : tous à moins de 365 jours.
      for (var m = 1; m <= 12; m++) {
        final year = m >= 11 ? 2026 : 2027;
        expect(_start('20 ${names[m - 1]} $year à 10h'), DateTime(year, m, 20, 10), reason: names[m - 1]);
      }
      expect(_start('20 aout 2027 à 10h'), DateTime(2027, 8, 20, 10));
      expect(_start('20 fevrier 2027 à 10h'), DateTime(2027, 2, 20, 10));
    });

    test('abréviations avec ou sans point', () {
      expect(_start('3 janv. 2027 à 10h'), DateTime(2027, 1, 3, 10));
      expect(_start('3 janv 2027 à 10h'), DateTime(2027, 1, 3, 10));
      expect(_start('3 fév. 2027 à 10h'), DateTime(2027, 2, 3, 10));
      expect(_start('3 avr 2027 à 10h'), DateTime(2027, 4, 3, 10));
      expect(_start('3 juil. 2027 à 10h'), DateTime(2027, 7, 3, 10));
      expect(_start('3 sept. 2027 à 10h'), DateTime(2027, 9, 3, 10));
    });

    test('abréviations de fin d\'année', () {
      expect(_start('3 oct 2027 à 10h'), DateTime(2027, 10, 3, 10));
      expect(_start('30 nov. 2026 à 10h'), DateTime(2026, 11, 30, 10));
      expect(_start('3 déc 2026 à 10h'), DateTime(2026, 12, 3, 10));
      expect(_start('1er déc. 2026 à 10h'), DateTime(2026, 12, 1, 10));
    });

    test('mois anglais (optionnel)', () {
      expect(_start('12 December 2026 at 14:30'), DateTime(2026, 12, 12, 14, 30));
    });
  });

  group('formats de date', () {
    test('numériques : / - . et année sur 2 chiffres', () {
      expect(_start('12/12/2026 à 14h'), DateTime(2026, 12, 12, 14));
      expect(_start('12-12-2026 à 14h'), DateTime(2026, 12, 12, 14));
      expect(_start('12.12.2026 à 14h'), DateTime(2026, 12, 12, 14));
      expect(_start('12/12/26 à 14h'), DateTime(2026, 12, 12, 14));
    });

    test('sans année : prochaine occurrence non passée', () {
      expect(_start('12/12 à 14h'), DateTime(2026, 12, 12, 14));
      expect(_start('12 décembre à 14h'), DateTime(2026, 12, 12, 14));
      expect(_start('20 janvier à 14h'), DateTime(2027, 1, 20, 14));
    });

    test('sans année et jour de la semaine : l\'année dont le jour correspond est préférée', () {
      // 14/12/2026 est un lundi, 14/12/2027 un mardi.
      final d = _parse(['Titre de test', 'Mardi 14 décembre à 10h']);
      expect(d.start, isNull); // 2027 : à plus de 365 jours
      expect(d.warnings.single, contains('mardi 14 décembre 2027'));
      expect(_start('Lundi 14 décembre à 10h'), DateTime(2026, 12, 14, 10));
    });

    test('jour de la semaine contraire à une date avec année : date gardée + avertissement', () {
      final d = _parse(['Titre de test', 'Lundi 12 décembre 2026 à 14h']);
      expect(d.start, DateTime(2026, 12, 12, 14));
      expect(d.warnings.single, contains('ne correspond pas'));
      expect(d.warnings.single, contains('samedi'));
    });

    test('date impossible (31/02) : ignorée', () {
      expect(_parse(['Titre de test', '31/02/2027 à 10h']).start, isNull);
      expect(_parse(['Titre de test', '31 février 2027 à 10h']).dateWithoutTime, isNull);
    });
  });

  group('plages de dates', () {
    test('« du 8 au 9 décembre 2026 »', () {
      final d = _parse(['Titre de test', 'Du 8 au 9 décembre 2026 de 9h à 17h']);
      expect(d.start, DateTime(2026, 12, 8, 9));
      expect(d.end, DateTime(2026, 12, 9, 17));
    });

    test('« du 28 novembre au 2 décembre » (sans année)', () {
      final d = _parse(['Titre de test', 'Du 28 novembre au 2 décembre, 10h - 12h']);
      expect(d.start, DateTime(2026, 11, 28, 10));
      expect(d.end, isNull); // 4 jours : au-delà de 72 h
      expect(d.warnings.single, contains('incompatible'));
    });

    test('« 8 - 9 décembre » et « 8 et 9 décembre »', () {
      for (final line in ['8 - 9 décembre 2026, 10h à 18h', '8 et 9 décembre, 10h à 18h']) {
        final d = _parse(['Titre de test', line]);
        expect(d.start, DateTime(2026, 12, 8, 10), reason: line);
        expect(d.end, DateTime(2026, 12, 9, 18), reason: line);
      }
    });

    test('plage trop longue pour le formulaire : fin vide + avertissement', () {
      final d = _parse(['Titre de test', 'Du 1 au 10 décembre 2026 de 9h à 17h']);
      expect(d.start, DateTime(2026, 12, 1, 9));
      expect(d.end, isNull);
      expect(d.warnings, [contains('incompatible')]);
    });

    test('une seule journée « 22h à 2h » : fin le lendemain', () {
      final d = _parse(['Titre de test', '12/12/2026 de 22h à 2h']);
      expect(d.end, DateTime(2026, 12, 13, 2));
    });
  });

  group('heures', () {
    test('formats acceptés', () {
      expect(_start('12/12/2026 à 14h'), DateTime(2026, 12, 12, 14));
      expect(_start('12/12/2026 à 14h30'), DateTime(2026, 12, 12, 14, 30));
      expect(_start('12/12/2026 à 14 h 30'), DateTime(2026, 12, 12, 14, 30));
      expect(_start('12/12/2026 à 14H00'), DateTime(2026, 12, 12, 14));
      expect(_start('12/12/2026 à 14:30'), DateTime(2026, 12, 12, 14, 30));
    });

    test('plages d\'heures', () {
      for (final (line, h1, m1, h2, m2) in [
        ('12/12/2026, 10h à 12h30', 10, 0, 12, 30),
        ('12/12/2026 de 10h à 12h', 10, 0, 12, 0),
        ('12/12/2026 · 9h00 – 17h00', 9, 0, 17, 0),
        ('12/12/2026 10h-12h', 10, 0, 12, 0),
      ]) {
        final d = _parse(['Titre de test', line]);
        expect(d.start, DateTime(2026, 12, 12, h1, m1), reason: line);
        expect(d.end, DateTime(2026, 12, 12, h2, m2), reason: line);
      }
    });

    test('« 25h », « 14h70 » et « 14.30 » ne sont pas des heures', () {
      for (final line in ['12/12/2026 à 25h', '12/12/2026 à 14h70', '12/12/2026 à 14.30']) {
        final d = _parse(['Titre de test', line]);
        expect(d.start, isNull, reason: line);
        expect(d.dateWithoutTime, DateTime(2026, 12, 12), reason: line);
      }
    });

    test('heure sur une autre ligne que la date', () {
      final d = _parse(['Titre de test', 'Samedi 12 décembre 2026', 'À partir de 15h']);
      expect(d.start, DateTime(2026, 12, 12, 15));
    });

    test('heure sans date : rien rempli, avertissement', () {
      final d = _parse(['Titre de test', 'Rendez-vous à 15h']);
      expect(d.start, isNull);
      expect(d.warnings.single, contains('Heure lue sans date'));
    });
  });

  group('bruit de lecture', () {
    test('O → 0 et l → 1 dans une date', () {
      expect(_start('O9/12/2026 à 14h'), DateTime(2026, 12, 9, 14));
      expect(_start('l2 décembre 2026 à 14h'), DateTime(2026, 12, 12, 14));
      expect(_start('12 décembre 2O26 à 14h'), DateTime(2026, 12, 12, 14));
    });

    test('O → 0 et I/| → 1 dans une heure', () {
      expect(_start('12/12/2026 à 1Oh3O'), DateTime(2026, 12, 12, 10, 30));
      expect(_start('12/12/2026 à 14hOO'), DateTime(2026, 12, 12, 14));
      expect(_start('12/12/2026 à |4:I5'), DateTime(2026, 12, 12, 14, 15));
    });

    test('jamais hors d\'une forme de date ou d\'heure', () {
      const text = 'salle io1 olivier, bloc o, il fait 2 hill';
      expect(PosterParser.fixOcrDigits(text), text);
      final d = _parse([_l('SALLE IO', height: 60), 'Bloc O']);
      expect(d.title, 'Salle io');
    });
  });

  group('dates limites', () {
    test('les dates sur une ligne de date limite sont ignorées', () {
      for (final line in [
        'Inscription avant le 10 décembre',
        'Inscriptions : 1er décembre 2026 à 10h',
        "Jusqu'au 5 décembre 2026",
        'Date limite : 5 décembre 2026 à 18h',
        'Clôture le 5/12/2026 à 18h',
        'Délai : 5 décembre 2026',
        'Avant le 5 décembre 2026 à 18h',
      ]) {
        final d = _parse(['Titre de test', 'Samedi 12 décembre 2026 à 14h', line]);
        expect(d.start, DateTime(2026, 12, 12, 14), reason: line);
      }
    });

    test('date limite seule : aucune date retenue', () {
      final d = _parse(['Titre de test', 'Inscription avant le 10 décembre à 18h']);
      expect(d.start, isNull);
      expect(d.dateWithoutTime, isNull);
    });

    test('« avant-première » n\'est pas une date limite', () {
      expect(_start('Avant-première le 18/12/2026 à 19h30'), DateTime(2026, 12, 18, 19, 30));
    });

    test('plusieurs dates : celle avec une heure, puis la plus grande, puis la plus tôt', () {
      expect(_parse(['Titre de test', '10 décembre 2026', '12 décembre 2026 à 14h']).start,
          DateTime(2026, 12, 12, 14));
      final bySize = _parse([
        'Titre de test',
        _l('15 décembre 2026 à 9h', height: 20),
        _l('20 décembre 2026 à 10h', height: 34),
      ]);
      expect(bySize.start, DateTime(2026, 12, 20, 10));
      expect(_parse(['Titre de test', '20 décembre 2026 à 10h', '15 décembre 2026 à 9h']).start,
          DateTime(2026, 12, 15, 9));
    });
  });

  group('date passée, proche ou sans heure', () {
    test('passée : non remplie, avertissement avec la date lue', () {
      final d = _parse(['Titre de test', '3 novembre 2026 à 10h']);
      expect(d.start, isNull);
      expect(d.warnings.single, 'Date détectée dans le passé : mardi 3 novembre 2026 à 10:00.');
    });

    test('dans moins de 15 minutes : non remplie', () {
      final d = _parse(['Titre de test', '9 novembre 2026 à 11h05']);
      expect(d.start, isNull);
      expect(d.warnings.single, contains('trop proche'));
    });

    test('date sans heure : début non rempli, date gardée à part', () {
      final d = _parse(['Titre de test', 'Samedi 12 décembre 2026']);
      expect(d.start, isNull);
      expect(d.dateWithoutTime, DateTime(2026, 12, 12));
      expect(d.warnings.single, contains('Date lue sans heure : samedi 12 décembre 2026'));
      expect(d.isEmpty, isFalse);
    });

    test('date passée sans heure : avertissement « passé »', () {
      final d = _parse(['Titre de test', '1er novembre 2026']);
      expect(d.dateWithoutTime, isNull);
      expect(d.warnings.single, contains('dans le passé'));
    });
  });

  group('lieu', () {
    test('préfixes retirés : Lieu :, Lieu, Adresse :, Où :', () {
      for (final line in ['Lieu : Amphi B', 'Lieu Amphi B', 'Adresse : Amphi B', 'Où : Amphi B', 'LIEU: Amphi B']) {
        expect(_parse(['Titre de test', line]).place, 'Amphi B', reason: line);
      }
    });

    test('lignes qui commencent par un mot de lieu', () {
      for (final line in ['Amphithéâtre Nord', 'Bibliothèque centrale', 'Terrain de basket', 'Auditorium A']) {
        expect(_parse([_l('Titre', height: 50), line]).place, line, reason: line);
      }
    });

    test('« Lieu : » seul : la ligne suivante est le lieu', () {
      expect(_parse([_l('Titre', height: 50), 'Lieu :', 'Salle polyvalente, bloc E']).place,
          'Salle polyvalente, bloc E');
    });

    test('« Cours de yoga » n\'est pas un lieu (mot entier)', () {
      expect(_parse([_l('Titre', height: 50), 'Cours de yoga pour tous']).place, isNull);
    });

    test('100 caractères au plus, coupé sur un mot', () {
      final long = 'Lieu : ${List.filled(30, 'mot').join(' ')}';
      final place = _parse(['Titre de test', long]).place!;
      expect(place.length, lessThanOrEqualTo(100));
      expect(place.endsWith('mot'), isTrue);
    });
  });

  group('prix', () {
    test('gratuit, entrée libre, free', () {
      for (final line in ['Gratuit', 'Entrée libre', 'FREE', 'Accès libre']) {
        final d = _parse(['Titre de test', line]);
        expect(d.isFree, isTrue, reason: line);
        expect(d.priceTnd, isNull, reason: line);
      }
    });

    test('formats de prix', () {
      for (final (line, value) in [
        ('Prix : 10 DT', 10.0),
        ('Tarif : 10 TND', 10.0),
        ('Participation : 10 dinars', 10.0),
        ('Entrée : 7', 7.0),
        ('5 DT', 5.0),
        ('5dt', 5.0),
        ('10,5 TND', 10.5),
        ('12.75 DT', 12.75),
      ]) {
        expect(_parse(['Titre de test', line]).priceTnd, value, reason: line);
      }
    });

    test('hors limites du formulaire : ignoré', () {
      expect(_parse(['Titre de test', 'Prix : 1500 DT']).priceTnd, isNull);
      expect(_parse(['Titre de test', 'Prix : 10,555 DT']).priceTnd, isNull);
    });

    test('aucun prix : vide, sans avertissement', () {
      final d = _parse(['Titre de test', 'Venez nombreux']);
      expect(d.priceFound, isFalse);
      expect(d.warnings, isEmpty);
    });

    test('ligne mixte : « gratuit » ET reste dans la description', () {
      final d = _parse([
        _l('GRAND TITRE', height: 60),
        'Équipes de 7 joueurs · Entrée libre',
        'Rendez-vous au stade',
        'Club organisateur',
      ]);
      expect(d.isFree, isTrue);
      expect(d.description, contains('Équipes de 7 joueurs'));
    });
  });

  group('titre', () {
    test('plusieurs lignes de même taille fusionnées dans l\'ordre de lecture', () {
      final d = _parse([
        _l('NUIT DU', height: 50),
        _l('CODE 2026', height: 52),
        'Samedi 12 décembre 2026 à 20h',
      ]);
      expect(d.title, 'Nuit du code 2026');
    });

    test('la plus grande ligne gagne ; lignes trop courtes ou sans lettres ignorées', () {
      final d = _parse([_l('**', height: 90), _l('2026', height: 80), _l('Journée portes ouvertes', height: 40)]);
      expect(d.title, 'Journée portes ouvertes');
    });

    test('capitales → phrase, sigles et mots avec chiffres gardés', () {
      expect(PosterParser.sentenceCase('HACKATHON IA ET IOT À ESPRIT'), 'Hackathon IA et IOT à ESPRIT');
      expect(PosterParser.sentenceCase('ATELIER CV & PFE'), 'Atelier CV & PFE');
      expect(PosterParser.sentenceCase('WORKSHOP 3D ET IEEE'), 'Workshop 3D et IEEE');
    });

    test('ligne plus petite AU-DESSUS de l\'ancre (majuscule accentuée plus haute) : reprise', () {
      final d = PosterParser.parse(
          const PosterOcrResult([
            PosterOcrLine('ASSEMBLEE', top: 120, height: 44, block: 0),
            PosterOcrLine('GÉNÉRALE DU', top: 172, height: 55, block: 0),
            PosterOcrLine('CLUB ROBOTIQUE', top: 234, height: 46, block: 0),
            PosterOcrLine('Mardi 15 déc. à 18h', top: 330, height: 30, block: 1),
          ]),
          posterNow);
      expect(d.title, 'Assemblee générale du club robotique');
    });

    test('hauteurs un peu différentes (58, 50, 47, 46, 61) : les 5 lignes forment le titre', () {
      final d = PosterParser.parse(
          const PosterOcrResult([
            PosterOcrLine('CONFÉRENCE :', top: 212, height: 58, block: 0),
            PosterOcrLine("L'INTELLIGENCE", top: 280, height: 50, block: 0),
            PosterOcrLine('ARTIFICIELLE AU', top: 340, height: 47, block: 0),
            PosterOcrLine('SERVICE DE', top: 397, height: 46, block: 0),
            PosterOcrLine("L'INGÉNIEUR", top: 452, height: 61, block: 1),
            PosterOcrLine('Une rencontre avec des chercheurs du domaine', top: 560, height: 26, block: 2),
            PosterOcrLine('Club organisateur', top: 700, height: 20, block: 3),
          ]),
          posterNow);
      expect(d.title, "Conférence : l'intelligence artificielle au service de l'ingénieur");
      expect(d.description, 'Une rencontre avec des chercheurs du domaine');
    });

    test('une année dans la ligne du titre reste dans le titre (pas une date)', () {
      expect(_parse([_l('FORUM ESPRIT', height: 62), _l('ENTREPRISES 2026', height: 60)]).title,
          'Forum ESPRIT entreprises 2026');
      expect(_parse([_l('FORUM ESPRIT ENTREPRISES', height: 62), _l('2026', height: 58)]).title,
          'Forum ESPRIT entreprises 2026');
    });

    test('bandeau et pied de page petits, ou ligne éloignée d\'un autre paragraphe : hors titre', () {
      final d = PosterParser.parse(
          const PosterOcrResult([
            PosterOcrLine('ESPRIT · VIE DE CAMPUS', top: 40, height: 14, block: 0),
            PosterOcrLine('NUIT DU CODE', top: 70, height: 64, block: 1),
            PosterOcrLine('ÉDITION SPÉCIALE', top: 300, height: 60, block: 2), // 166 px plus bas
            PosterOcrLine('Club Info ESPRIT', top: 760, height: 14, block: 3),
          ]),
          posterNow);
      expect(d.title, 'Nuit du code');
    });

    test('un titre en minuscules et majuscules reste tel quel', () {
      expect(_parse([_l('Café des langues', height: 50)]).title, 'Café des langues');
    });

    test('80 caractères au plus, coupé sur un mot', () {
      final d = _parse([_l(List.filled(20, 'TRÈS').join(' '), height: 50)]);
      expect(d.title!.length, lessThanOrEqualTo(80));
      expect(d.title!.endsWith('très'), isTrue);
    });
  });

  group('description', () {
    test('sans titre, lieu, date limite ni lignes d\'infos pures', () {
      final d = _parse([
        _l('GRAND TITRE', height: 60),
        'Samedi 12 décembre 2026 à 14h',
        'Lieu : Amphi B',
        'Une soirée de jeux de société',
        'Prix : 5 DT',
        'Inscription avant le 10 décembre',
        'Club organisateur',
      ]);
      expect(d.description, 'Une soirée de jeux de société');
    });

    test('lignes petites (< 60 % de la médiane) exclues', () {
      final d = _parse([
        _l('GRAND TITRE', height: 60),
        'Une soirée de jeux de société',
        _l('mentions légales du club', height: 10),
        'Ambiance conviviale garantie',
        'Club organisateur',
      ]);
      expect(d.description, 'Une soirée de jeux de société\nAmbiance conviviale garantie');
    });

    test('bandeau du haut et pied de page (10 % du texte) exclus, même de taille normale', () {
      final d = PosterParser.parse(
          const PosterOcrResult([
            PosterOcrLine('Association des étudiants', top: 0, height: 28),
            PosterOcrLine('GRAND TITRE', top: 100, height: 60),
            PosterOcrLine('Une soirée de jeux de société', top: 250, height: 28),
            PosterOcrLine('www.club-exemple.tn', top: 600, height: 28),
          ]),
          posterNow);
      expect(d.description, 'Une soirée de jeux de société');
    });

    test('1000 caractères au plus', () {
      final d = _parse([
        _l('GRAND TITRE', height: 60),
        'debut',
        for (var i = 0; i < 60; i++) 'Une ligne de description numéro $i assez longue',
        'fin',
      ]);
      expect(d.description!.length, lessThanOrEqualTo(1000));
    });
  });

  group('entrées vides ou illisibles', () {
    test('aucune ligne', () {
      final d = PosterParser.parse(PosterOcrResult.empty, posterNow);
      expect(d.isEmpty, isTrue);
      expect(d.warnings, isEmpty);
    });

    test('symboles et chiffres seuls', () {
      final d = _parse(['***', '— · —', '12345', '!!']);
      expect(d.isEmpty, isTrue);
    });

    test('arabe seul : rien lu, avertissement « caractères latins »', () {
      final d = _parse(['حفل التخرج', 'يوم السبت']);
      expect(d.isEmpty, isTrue);
      expect(d.mostlyNonLatin, isTrue);
      expect(d.warnings, [PosterParser.latinOnlyWarning]);
    });

    test('lignes arabes ignorées dans une affiche surtout latine', () {
      final d = _parse([_l('SOIRÉE CINÉMA', height: 60), 'سينما', 'Samedi 12 décembre 2026 à 20h']);
      expect(d.title, 'Soirée cinéma');
      expect(d.start, DateTime(2026, 12, 12, 20));
      expect(d.warnings, isEmpty);
    });
  });

  test('compte rendu de débogage : lignes (bloc, top, hauteur, écart) puis champs', () {
    final fx = posterFixtures[3];
    final report = PosterParser.debugReport(fx.ocr, PosterParser.parse(fx.ocr, posterNow));
    expect(report.every((l) => l.startsWith('[PosterScan]')), isTrue);
    expect(report[1], '[PosterScan] #0 bloc=0 top=100 h=56 écart=- « SOIRÉE CINÉMA EN PLEIN AIR »');
    expect(report[2], '[PosterScan] #1 bloc=1 top=190 h=28 écart=34 « Vendredi 18/12/2026 à 19h30 »');
    expect(report, contains('[PosterScan] prix: trouvé → 5.0'));
    expect(report, contains('[PosterScan] description: non trouvé'));
  });

  test('formats d\'affichage', () {
    expect(PosterParser.formatDay(DateTime(2026, 12, 12)), 'samedi 12 décembre 2026');
    expect(PosterParser.formatDateTime(DateTime(2026, 12, 12, 9, 5)), 'samedi 12 décembre 2026 à 09:05');
  });
}
