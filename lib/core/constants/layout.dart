import 'package:flutter/widgets.dart';

/// Constantes de mise en page partagées (grille 8 dp, sauf exceptions
/// explicitement demandées par la maquette).

/// Marge horizontale de tout contenu d'écran. Les fonds pleine largeur
/// (héro, champs de couleur) ne la prennent pas : seul leur contenu la prend.
const double kPagePadding = 20.0;

/// Espace vertical entre deux sections.
const double kSectionGap = 32.0;

/// Espace entre le titre d'une section et son contenu.
const double kHeaderGap = 12.0;

/// Espace entre deux cartes d'une même grille (les deux axes).
const double kCardGap = 12.0;

/// Cartes de chiffres : rayon, remplissage interne et ombre portée
/// (floutage 16, décalage vertical 4, noir à 5 %).
const double kStatCardRadius = 20.0;
const double kStatCardPadding = 14.0;
const BoxShadow kStatCardShadow = BoxShadow(
  color: Color(0x0D000000),
  blurRadius: 16,
  offset: Offset(0, 4),
);

/// Pastille d'icône des cartes de chiffres.
const double kIconTileSize = 44.0;
const double kIconTileRadius = 12.0;
const double kIconTileIconSize = 22.0;

/// Héro de l'accueil visiteur.
const double kHeroBottomRadius = 32.0;
const double kHeroCircleLarge = 180.0;
const double kHeroCircleSmall = 110.0;
const double kHeroSubtitleMaxWidth = 300.0;
const double kPillHeight = 36.0;

/// Espace réservé en bas d'un écran pour la barre de navigation flottante.
const double kFloatingNavInset = 96.0;

/// Au-delà de cette largeur, la mise en page passe en mode large.
const double kCompactBreakpoint = 600.0;

/// Largeur maximale du contenu en mode large.
const double kContentMaxWidth = 720.0;
