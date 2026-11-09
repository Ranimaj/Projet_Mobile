import 'package:campusconnect/screens/evenements/poster_ocr.dart';

/// Les 5 affiches de référence, sous forme de lignes de texte « propres »
/// (comme si la lecture était parfaite). Hauteurs proches d'une vraie
/// affiche : titre grand, infos moyennes, bandeau et pied de page petits,
/// placés aux bords.
///
/// « Maintenant » commun : lundi 9 novembre 2026 à 11:00.
final DateTime posterNow = DateTime(2026, 11, 9, 11);

class PosterFixture {
  final String file;
  final List<PosterOcrLine> lines;
  final String title;
  final DateTime start;
  final DateTime? end;
  final String place;
  final double? price;
  final bool free;
  final String? description;
  final String category;

  const PosterFixture({
    required this.file,
    required this.lines,
    required this.title,
    required this.start,
    this.end,
    required this.place,
    this.price,
    this.free = false,
    this.description,
    required this.category,
  });

  PosterOcrResult get ocr => PosterOcrResult(lines);
}

/// Observé sur émulateur : le DÉCOUPAGE en lignes que la lecture réelle (ML
/// Kit) a produit — un champ réparti sur plusieurs lignes, la date et l'heure
/// sur deux lignes, « ESPRIT » seul après le lieu, « ASSEMBLEE » sans accent.
/// Les hauteurs et écarts sont ESTIMÉS (pas encore de journal [PosterScan]) :
/// cadres plus hauts quand une majuscule porte un accent, 6 à 10 px d'écart
/// dans un paragraphe, 30 à 100 px entre paragraphes. À remplacer par les
/// valeurs du journal dès qu'il est disponible.
///
/// L'accent perdu par la lecture (« ASSEMBLEE ») n'est pas corrigé : c'est
/// une limite de la lecture, le résultat attendu la garde.
final List<PosterFixture> observedPosterFixtures = [
  PosterFixture(
    file: 'affiche_2_conference.jpg (observé)',
    lines: [
      _l('CONFÉRENCE :', 212, 58, 0),
      _l("L'INTELLIGENCE", 280, 50, 0),
      _l('ARTIFICIELLE AU', 340, 47, 0),
      _l('SERVICE DE', 397, 46, 0),
      _l("L'INGÉNIEUR", 452, 61, 1),
      _l('Jeudi 17 décembre 2026', 560, 30, 2),
      _l('de 10h à 12h30', 598, 29, 2),
      _l('Lieu : Amphi B, bloc A – ESPRIT', 660, 27, 3),
      _l('Gratuit · Ouvert à tous les étudiants', 712, 25, 4),
    ],
    title: "Conférence : l'intelligence artificielle au service de l'ingénieur",
    start: DateTime(2026, 12, 17, 10),
    end: DateTime(2026, 12, 17, 12, 30),
    place: 'Amphi B, bloc A – ESPRIT',
    free: true,
    category: 'Conférence',
  ),
  PosterFixture(
    file: 'affiche_3_carriere.jpg (observé)',
    lines: [
      _l('FORUM ESPRIT', 150, 62, 0),
      _l('ENTREPRISES 2026', 222, 60, 0),
      _l('Du 8 au 9 décembre 2026 · 9h00 – 17h00', 330, 30, 1),
      _l('Lieu : Hall principal, campus', 390, 28, 2),
      _l('ESPRIT', 424, 27, 2),
      _l('Rencontrez des recruteurs, déposez votre CV', 490, 25, 3),
      _l('et décrochez un stage PFE', 521, 25, 3),
      _l('GRATUIT', 600, 34, 4),
    ],
    title: 'Forum ESPRIT entreprises 2026',
    start: DateTime(2026, 12, 8, 9),
    end: DateTime(2026, 12, 9, 17),
    place: 'Hall principal, campus ESPRIT',
    free: true,
    description: 'Rencontrez des recruteurs, déposez votre CV et décrochez un stage PFE',
    category: 'Carrière',
  ),
  PosterFixture(
    file: 'affiche_5_difficile.jpg (observé)',
    lines: [
      _l('ASSEMBLEE', 120, 44, 0),
      _l('GÉNÉRALE DU', 172, 55, 0),
      _l('CLUB ROBOTIQUE', 234, 46, 0),
      _l('Mardi 15 déc. à 18h', 330, 30, 1),
      _l('Salle des clubs, bloc C', 385, 27, 2),
      _l('Élection du nouveau bureau', 440, 26, 3),
      _l('Inscription avant le 10 décembre', 520, 20, 4),
    ],
    title: 'Assemblee générale du club robotique',
    start: DateTime(2026, 12, 15, 18),
    place: 'Salle des clubs, bloc C',
    description: 'Élection du nouveau bureau',
    category: 'Vie associative',
  ),
];

PosterOcrLine _l(String text, double top, double height, [int block = 0]) =>
    PosterOcrLine(text, top: top, height: height, block: block);

final List<PosterFixture> posterFixtures = [
  PosterFixture(
    file: 'affiche_1_sport.jpg',
    lines: [
      _l('ESPRIT · VIE DE CAMPUS', 40, 14, 0),
      _l('TOURNOI DE FOOTBALL INTER-CLASSES', 120, 64, 1),
      _l('Samedi 12 décembre 2026 à 14h00', 260, 30, 2),
      _l("Lieu : Stade de l'ESPRIT, Ghazala", 310, 26, 3),
      _l('Équipes de 7 joueurs · Entrée libre', 360, 24, 4),
      _l('Club Sport ESPRIT', 760, 14, 5),
    ],
    title: 'Tournoi de football inter-classes',
    start: DateTime(2026, 12, 12, 14),
    place: "Stade de l'ESPRIT, Ghazala",
    free: true,
    description: 'Équipes de 7 joueurs · Entrée libre',
    category: 'Sport',
  ),
  PosterFixture(
    file: 'affiche_2_conference.jpg',
    lines: [
      _l('CONFÉRENCE :', 80, 48, 0),
      _l("L'INTELLIGENCE ARTIFICIELLE", 136, 48, 0),
      _l('AU SERVICE', 192, 48, 0),
      _l("DE L'INGÉNIEUR", 248, 48, 0),
      _l('Jeudi 17 décembre 2026, de 10h à 12h30', 340, 28, 1),
      _l('Lieu : Amphi B, bloc A – ESPRIT', 390, 26, 2),
      _l('Gratuit · Ouvert à tous les étudiants', 440, 24, 3),
    ],
    title: "Conférence : l'intelligence artificielle au service de l'ingénieur",
    start: DateTime(2026, 12, 17, 10),
    end: DateTime(2026, 12, 17, 12, 30),
    place: 'Amphi B, bloc A – ESPRIT',
    free: true,
    category: 'Conférence',
  ),
  PosterFixture(
    file: 'affiche_3_carriere.jpg',
    lines: [
      _l('FORUM ESPRIT ENTREPRISES 2026', 80, 60, 0),
      _l('Du 8 au 9 décembre 2026 · 9h00 – 17h00', 170, 28, 1),
      _l('Lieu : Hall principal, campus ESPRIT', 220, 26, 2),
      _l('Rencontrez des recruteurs, déposez votre CV et décrochez un stage PFE', 280, 24, 3),
      _l('Gratuit', 340, 30, 4),
    ],
    title: 'Forum ESPRIT entreprises 2026',
    start: DateTime(2026, 12, 8, 9),
    end: DateTime(2026, 12, 9, 17),
    place: 'Hall principal, campus ESPRIT',
    free: true,
    description: 'Rencontrez des recruteurs, déposez votre CV et décrochez un stage PFE',
    category: 'Carrière',
  ),
  PosterFixture(
    file: 'affiche_4_culture.jpg',
    lines: [
      _l('SOIRÉE CINÉMA EN PLEIN AIR', 100, 56, 0),
      _l('Vendredi 18/12/2026 à 19h30', 190, 28, 1),
      _l("Lieu : Cour de l'école", 240, 26, 2),
      _l('Prix : 5 DT', 290, 30, 3),
    ],
    title: 'Soirée cinéma en plein air',
    start: DateTime(2026, 12, 18, 19, 30),
    place: "Cour de l'école",
    price: 5,
    category: 'Culture',
  ),
  PosterFixture(
    file: 'affiche_5_difficile.jpg',
    lines: [
      _l('ASSEMBLÉE GÉNÉRALE DU CLUB ROBOTIQUE', 60, 50, 0),
      _l('Mardi 15 déc. à 18h', 150, 30, 1),
      _l('Salle des clubs, bloc C', 200, 26, 2),
      _l('Élection du nouveau bureau', 250, 24, 3),
      _l('Inscription avant le 10 décembre', 300, 18, 4),
    ],
    title: 'Assemblée générale du club robotique',
    start: DateTime(2026, 12, 15, 18),
    place: 'Salle des clubs, bloc C',
    description: 'Élection du nouveau bureau',
    category: 'Vie associative',
  ),
];
