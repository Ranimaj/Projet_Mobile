# CampusConnect — Nouvelle UI « sombre et orange » (clair + sombre)

Date : 2026-10-28 · Branche : `nouvelle-ui` · Module porteur : Gestion des Utilisateurs (+ squelette partagé)

## 1. Objectif

Refondre l'interface de CampusConnect dans la direction validée sur les maquettes
« direction sombre et orange » : fond quasi noir ou blanc cassé selon le thème, photos
pleines, boutons pilule, barre de navigation flottante à pastilles rondes, accent orange,
icônes vectorielles uniquement, aucun emoji. Les deux thèmes (clair et sombre) sont
complets et la mise en page s'adapte à la largeur et à la hauteur de l'écran.

La refonte porte sur le squelette partagé et sur les écrans du module Utilisateurs. Les
écrans des quatre autres modules héritent du nouveau thème sans être retouchés, pour ne
pas entrer en conflit avec les branches des coéquipiers.

## 2. Décisions prises (et risques assumés)

| Sujet | Décision | Note |
|---|---|---|
| Couleur principale | Orange `#FF6A1F` (clair) / `#FF7A3A` (sombre) | Le cahier des charges (section 6) prescrit indigo → violet avec l'orange en accent. Choix assumé par le porteur du projet ; le violet disparaît de l'app. |
| OCR carte étudiant | Abandonné | Le cahier le liste comme fonctionnalité avancée n° 1 du module. Remplacé par : photo de la carte envoyée par l'étudiant, validée dans l'app par un admin, plus la gestion des rôles dans l'app (exigée aussi par le cahier). Risque de note accepté par le porteur. |
| Navigation | Barre flottante à 5 pastilles (Accueil, Marché, Annonces, Événements, Stages) ; le profil s'ouvre depuis l'avatar de l'en-tête | Remplace les 6 onglets actuels. |
| Thème au lancement | Suit le système ; bascule Clair / Sombre / Système dans le profil, mémorisée avec `shared_preferences` | Le cahier demande `SharedPreferences` pour le mode de thème. |
| Filière | Liste déroulante des départements ESPRIT + « Autre » (texte libre) | Remplace le champ texte libre actuel. |
| Campus | ESPRIT Ghazela uniquement, stocké dans le profil pour les futurs filtres de distance | Constante, pas de sélecteur pour l'instant. |
| Typographie | Outfit (titres) + Inter (texte), déjà en place via `google_fonts` | Aucun changement de police. |
| Graphiques | `fl_chart` | Nouvelle dépendance. |
| Push à la validation d'une carte | Hors périmètre (Cloud Functions, plan Blaze) | Le statut se met à jour en direct via un listener Firestore. |

## 3. Système de design

Tout est défini en jetons dans `lib/core/theme/` et consommé via `Theme.of(context)` ou
une extension `AppTokens`. Aucune valeur hexadécimale ni taille de police dans un écran.

### 3.1 Couleurs

| Jeton | Clair | Sombre | Usage |
|---|---|---|---|
| primary | `#FF6A1F` | `#FF7A3A` | actions, pastille active, liens |
| primarySoft | `#FFF1E8` | `#FF6A1F` à 16 % | fond des puces et cercles d'icône |
| onPrimarySoft | `#E8661B` | `#FF9A5F` | texte sur primarySoft |
| background | `#F6F6F9` | `#121214` | fond des écrans |
| surface | `#FFFFFF` | `#1C1C21` | cartes, feuilles, barre flottante |
| surfaceMuted | `#F0F0F4` | `#242429` | tuiles de stats, champs |
| outline | `#EEEDF2` | `#2A2A2F` | bord fin des cartes en sombre, filets |
| textPrimary | `#1C1A33` | `#F4F2F0` | titres, corps |
| textSecondary | `#7C7A8C` | `#9A969B` | légendes, méta |
| success / successSoft | `#1B7A43` / `#E6F6EC` | `#4ADE80` / `#4ADE80` à 16 % | vérifié, à jour, « Gratuit » |
| warning / warningSoft | `#B45309` / `#FEF3C7` | `#FBBF24` / `#FBBF24` à 16 % | en attente de synchro |
| danger / dangerSoft | `#DD3333` / `#FEE2E2` | `#F87171` / `#F87171` à 16 % | erreurs, refus, suppression |
| handle | `#E2E1E8` | `#3A3A40` | poignée de feuille, points inactifs |

Valeurs finales après le test de contraste AA (les jetons ci-dessus qui échouaient ont été
ajustés au plus petit pas qui passe ; en sombre, les « à 16 % » sont pré-mélangés sur `surface`) :

| Jeton | Clair | Sombre |
|---|---|---|
| primary | `#F9671E` | `#EC7136` |
| onPrimarySoft | `#B75115` | `#FF9A5F` |
| textSecondary | `#767586` | `#9A969B` |
| primarySoft | `#FFF1E8` | `#402821` |
| successSoft | `#E6F6EC` | `#233B30` |
| warningSoft | `#FEF3C7` | `#403621` |
| dangerSoft | `#FEE2E2` | `#3F2A2E` |

Ombres : en clair, ombre douce `0 2 10 rgba(28,26,51,.06)` sur les cartes et `0 8 24
rgba(28,26,51,.12)` sur la barre flottante ; en sombre, pas d'ombre, bord `outline` de 1 px.
Les photos reçoivent un voile dégradé (noir 85 % → 0 %) quand du texte est posé dessus.
Les boutons posés sur photo sont toujours blancs à texte sombre, quel que soit le thème.

Contraste : chaque paire texte/fond ci-dessus respecte WCAG AA (≥ 4.5:1 pour le texte
courant, ≥ 3:1 pour les grands titres). L'orange sur blanc n'est utilisé que pour des
textes ≥ 14 px en gras ou des icônes.

### 3.2 Formes et espacement

Grille 8 dp (4, 8, 12, 16, 20, 24, 32). Marge d'écran `kPagePadding` = 20. Rayons :
cartes 20, cartes photo 20, feuille sur photo 28 en haut, champs 14, puces 10 (statut) ou
pleine (filtre), boutons pilule et pastilles pleins. Pastilles rondes : 38 dp (en-tête),
46 dp (barre flottante), 34 dp (ligne de réglage). Cibles tactiles ≥ 48 dp grâce au
rembourrage des zones d'appui.

### 3.3 Composants partagés (`lib/widgets/`)

| Widget | Rôle | Remplace |
|---|---|---|
| `RoundIconButton` | pastille ronde : variantes `surface`, `soft` (orange pâle), `primary`, `onPhoto` (blanc) | — |
| `PillButton` | pilule pleine largeur ou compacte : `primary`, `ghost` (contour orange), `dark` (surface sombre sur photo) | `PrimaryButton` + `PillButton` actuels |
| `StatusChip` | puce 10 px de rayon : `soft`, `success`, `warning`, `danger`, `onPhoto` | `StatusBadge` |
| `FilterChipPill` | puce ronde `on` (orange) / `off` (surface) avec icône | `ChipTheme` |
| `PhotoCard` | photo en haut, corps en bas ; puce et cœur posés sur la photo | cartes d'article / offre de l'accueil |
| `FeaturedCard` | photo pleine, voile orange à gauche, puce, titre, méta, pilule sombre | — |
| `HeroSheetScaffold` | photo ou dégradé en haut, feuille `surface` à coins 28 avec poignée, boutons ronds par-dessus, barre d'action fixe optionnelle | `GradientScaffold` |
| `FloatingNavBar` | 5 pastilles rondes dans une pilule flottante, active en orange | `BottomNavigationBar` |
| `StatTile` | chiffre + libellé sur `surfaceMuted` | `_StatTile` du profil |
| `SettingRow` | icône dans cercle `soft`, titre, sous-titre, fin (chevron, interrupteur, puce) | `SettingsTile` |
| `SettingGroup` | groupe `surfaceMuted` à coins 16 qui empile des `SettingRow` | `SectionCard` |
| `SyncChip` | « À jour » vert, « N en attente » orange, « Hors ligne » ambre | `OfflineBanner` (conservé, restylé, pour les listes) |
| `SearchPill` | champ de recherche en pilule avec bouton filtre orange | `_SearchField` |
| `InitialsAvatar` | cercle orange avec initiales, ou photo, badge de vérification optionnel | `_Badge` + avatar du profil |
| `SkeletonBox` | shimmer sur `surfaceMuted` | `_Skeleton` |
| `charts/AreaLineChart`, `charts/DonutChart`, `charts/HBarChart` | enveloppes `fl_chart` : couleurs du thème, info-bulle au toucher, état vide, animation ≤ 300 ms | — |

Chaque composant a un test de widget dans les deux thèmes et un test « aucun texte sous
13 px ».

### 3.4 Mise en page adaptative

Aucune largeur fixe de téléphone. Règles :

- `LayoutBuilder` à la racine de chaque écran : largeur < 600 dp = compact, ≥ 600 = étendu.
- Compact : une colonne, carrousels dont la carte mesure 62 % de la largeur disponible,
  grilles à 2 colonnes.
- Étendu : contenu centré, largeur max 720 dp ; grilles à 3 colonnes ; la barre flottante
  garde 5 pastilles et se centre sur 480 dp max.
- Hauteur : la feuille sur photo prend `max(40 %, contenu)` de la hauteur ; la photo de
  couverture mesure 34 % de la hauteur, bornée entre 200 et 320 dp. Sur un écran très
  bas (< 560 dp de haut, clavier ouvert), la photo se réduit à 120 dp.
- `MediaQuery.textScaler` jusqu'à 1.3 sans débordement ; les tests vérifient 360 × 640,
  412 × 915 et 800 × 1280.
- Rien n'est tronqué silencieusement : titres sur 2 lignes maximum avec points de
  suspension, méta sur 1 ligne.

### 3.5 Thème

`AppTheme.light` et `AppTheme.dark` construits depuis un `ColorScheme` et les jetons.
`ThemeProvider` (ChangeNotifier) expose `ThemeMode` ; persisté dans `shared_preferences`
sous la clé `theme_mode`. `MaterialApp` reçoit `theme`, `darkTheme`, `themeMode`.
Animations ≤ 200 ms, désactivées quand `MediaQuery.disableAnimations` est vrai.

## 4. Navigation

- `AppShell` : `IndexedStack` de 5 écrans + `FloatingNavBar`. Le corps passe sous la
  barre ; chaque liste reçoit un rembourrage bas de 96 dp.
- L'avatar de l'en-tête de l'accueil ouvre `ProfileScreen` par `Navigator.push`.
- Rôle admin : le profil affiche un groupe « Administration » avec « Utilisateurs »,
  « Cartes à vérifier » et « Statistiques ». Rôle visiteur : inchangé (`VisitorHomeScreen`),
  restylé.
- `_RootRouter` : au premier lancement (`onboarding_seen` absent des préférences),
  affiche `OnboardingScreen` avant l'écran visiteur.

## 5. Écrans

### 5.1 Onboarding (nouveau)

Trois pages à glisser : collage de photos campus en bulles rondes avec trois bulles
d'icône orange (étiquette, calendrier, mallette) sur la première ; les deux suivantes
utilisent une photo pleine. Feuille en bas : titre Outfit 800 avec un segment en italique
orange, sous-titre, points de pagination, `PillButton.primary` « Commencer », lien
« Déjà un compte ? Se connecter ». Les photos viennent de `assets/images/onboarding/`
(trois fichiers JPG libres de droits ajoutés au dépôt, ≤ 200 Ko chacun). « Commencer »
ouvre l'inscription, « Se connecter » la connexion ; les deux marquent `onboarding_seen`.

### 5.2 Accueil visiteur (restyle)

Même contenu qu'aujourd'hui (héros, quatre sections, appel à l'action bas). Héros : photo
pleine avec voile sombre, titre blanc, deux `StatPill`. Sections en `PhotoCard` et
`FeaturedCard`. Barre basse fixe : « Créer un compte étudiant » (`primary`) et
« Se connecter » (`ghost`).

### 5.3 Authentification (restyle)

`LoginScreen`, `RegisterScreen`, `ForgotPasswordScreen`, `OtpVerificationScreen`,
`ChangePasswordScreen` passent de `GradientScaffold` à `HeroSheetScaffold` : en haut un
dégradé orange avec cercles décoratifs discrets (pas de photo, pour la vitesse), titre et
sous-titre blancs, bouton retour rond blanc ; en bas la feuille `surface` avec les champs
(`InputDecorationTheme` du thème : fond `surfaceMuted`, rayon 14, bord orange au focus),
`PillButton.primary` pleine largeur, lien secondaire en orange, rangée Google. Les champs
soulignés blancs (`UnderlineTextField`) disparaissent. Le bouton « Déverrouiller par
biométrie » devient une `SettingRow`-like en pilule `ghost` avec l'icône empreinte.

### 5.4 Accueil connecté (restyle + graphiques)

Dans l'ordre : en-tête (avatar → profil, « Campus » / « ESPRIT Ghazela », cloche avec point
orange), `SyncChip` et date, `SearchPill`, « À la une » (carrousel `FeaturedCard` des
annonces officielles épinglées puis du prochain événement ; points de pagination),
« Modules » (quatre `FilterChipPill` qui changent d'onglet, avec compteur en sous-texte),
carte « Complète ton profil » (anneau orange `fl_chart` + `PillButton` compact),
« Cette semaine » (carte événement avec bloc date orange pâle), « Stages pour toi »
(`PhotoCard` compactes avec initiale et % de correspondance s'il existe), « Vente & Don »
(grille de `PhotoCard`), puis « Mon activité, 7 jours » : `AreaLineChart` des actions de
l'utilisateur (annonces, articles, inscriptions, candidatures) sur 7 jours, calculé depuis
les providers existants. Toutes les données viennent des providers actuels ; aucune
nouvelle requête.

### 5.5 Profil (restyle)

`HeroSheetScaffold` : couverture (photo `assets/images/cover_campus.jpg`, voile), boutons
ronds retour, partager et modifier ; feuille avec `InitialsAvatar` à cheval sur la
couverture (badge orange ✓ si `isVerifiedStudent`), nom, puces d'état (`Étudiant vérifié`
ou `Vérification en attente` ou `Carte refusée`, `Email vérifié`, `Téléphone vérifié`),
filière · année, trois `StatTile` (annonces, ventes, candidatures de l'utilisateur, depuis
les providers), puis :

- `SettingRow` « Carte étudiant » : sous-titre selon `studentCard.status` (aucune : « Envoyer
  une photo de ta carte » ; pending : « En cours de validation » ; verified : « Validée le
  … » ; rejected : « Refusée : <motif> »). Ouvre `StudentCardScreen`.
- `SettingRow` « Connexion biométrique » avec interrupteur (préférence locale existante).
- `SettingRow` « Thème » : Clair / Sombre / Système dans une feuille de choix.
- Groupe « Compte » : modifier mes informations, changer le mot de passe (si fournisseur
  mot de passe), numéro de téléphone (puce « Vérifié » ou action OTP), mes données (export
  JSON), supprimer le compte. Groupe « Sécurité » : 2FA (interrupteur existant), mode hors
  ligne (lecture seule, état de la file). Groupe « Administration » si admin.
- Barre fixe en bas : « Membre depuis <mois année> » et `PillButton.primary`
  « Modifier le profil ». « Déconnexion » reste en bas de la feuille en `ghost` rouge.

La bannière de vérification d'email existante est conservée, restylée en carte
`warningSoft`.

### 5.6 Modifier le profil (restyle + filière)

Même formulaire ; la filière devient un `DropdownButtonFormField` sur
`AppConstants.departments` = Génie Informatique, Génie Civil, Génie Électromécanique,
Génie Télécom, Génie Industriel, Business, Autre. « Autre » affiche un champ texte.
Le champ `campus` est fixé à `ESPRIT Ghazela` à la création du profil.

### 5.7 Carte étudiant (nouveau, côté étudiant)

`StudentCardScreen` : explication, aperçu de la photo choisie (galerie ou appareil via
`image_picker`, compressée ≤ 1080 px par `StorageService`), `PillButton.primary`
« Envoyer pour validation ». En ligne : envoi vers `student_cards/{uid}/{timestamp}.jpg`
puis écriture `studentCard = {status: pending, imagePath, submittedAt}` dans le profil.
Hors ligne : le fichier est copié dans le dossier de l'app, une action
`uploadStudentCard` (nouveau `QueueActionType`) est mise dans la file existante avec le
chemin local ; au retour du réseau, `OfflineQueueService` envoie le fichier puis le
document. L'écran montre « En attente de connexion » tant que l'action est en file.
Après envoi, l'écran affiche le statut et, si refusée, le motif et un bouton « Renvoyer ».

### 5.8 Administration (nouveau)

- `AdminUsersScreen` : liste `ListView.builder` des utilisateurs (recherche par nom ou
  email avec `TextField.onChanged` + debounce, filtres rôle et statut de carte en
  `FilterChipPill`). Chaque ligne : avatar, nom, puce rôle, puce statut. Appui :
  feuille d'actions « Changer le rôle » (étudiant / recruteur / admin, confirmation) et
  « Désactiver le compte » (`disabled: true`, l'utilisateur est déconnecté au prochain
  démarrage via `_RootRouter`).
- `AdminCardReviewScreen` : `HeroSheetScaffold` avec la photo de la carte en haut (zoom
  plein écran au toucher), feuille avec nom, filière, année, email, date d'envoi ; barre
  fixe « Refuser » (`ghost` rouge, demande un motif) et « Valider » (`primary`). Valider
  écrit `studentCard.status = verified`, `reviewedBy`, `reviewedAt` et
  `isVerifiedStudent = true`. La file des cartes en attente est l'onglet par défaut de
  `AdminUsersScreen` (filtre `pending`).
- `AdminAnalyticsScreen` : sélecteur de période (7 / 30 / 90 jours), deux `StatTile`
  (inscrits sur la période avec variation en % vs période précédente ; cartes en attente),
  `AreaLineChart` « Inscriptions par jour » avec info-bulle, `DonutChart` « Par rôle »,
  `HBarChart` « Vérification des cartes » (validées, en attente, refusées). Les données
  sont agrégées côté client par `UserStatsService.aggregate(List<AppUser>, période)`, une
  fonction pure testée unitairement. Sur le plan Spark, la collection `users` reste
  lisible en une requête tant qu'elle compte moins de quelques milliers de documents ;
  au-delà, note dans `docs/decisions.md`.

## 6. Données et règles

### 6.1 `AppUser` (ajouts)

```
campus: String            // 'ESPRIT Ghazela'
studentId: String?        // identifiant saisi par l'étudiant
disabled: bool            // défaut false, admin uniquement
studentCard: {
  status: none | pending | verified | rejected
  imagePath: String?      // chemin Storage
  submittedAt: DateTime?
  reviewedBy: String?     // uid admin
  reviewedAt: DateTime?
  rejectReason: String?
}
```

`editableFields` gagne `campus`, `studentId` et `studentCard` ; mais les règles Firestore
n'autorisent le propriétaire à écrire `studentCard` que vers `status: pending` avec
`imagePath` et `submittedAt`, jamais `verified` / `rejected` ni les champs `reviewed*`.
`isVerifiedStudent`, `role` et `disabled` restent admin seulement.

### 6.2 `firestore.rules` (ajouts dans `match /users/{userId}`)

- `touchesProtectedUserFields()` ajoute `disabled`.
- Nouvelle fonction `studentCardChangeIsSubmission()` : vrai si `studentCard` n'est pas
  modifié, ou si le nouveau `studentCard.status == 'pending'` et que `reviewedBy`,
  `reviewedAt`, `rejectReason` sont absents.
- `allow update` propriétaire : `&& studentCardChangeIsSubmission()`.
- `allow create` : `studentCard.status == 'none'` et `disabled == false`.

### 6.3 `storage.rules` (ajout)

```
match /student_cards/{userId}/{file} {
  allow write: if isSignedIn() && request.auth.uid == userId && isSmallImage();
  allow read: if isSignedIn() && (request.auth.uid == userId
      || firestore.get(/databases/(default)/documents/users/$(request.auth.uid)).data.role == 'admin');
}
```

### 6.4 Préférences locales (`shared_preferences`, nouveau)

`theme_mode`, `onboarding_seen`. Les préférences existantes sur Hive (`prefs_box`) ne
bougent pas.

## 7. Hors ligne

- Lecture : inchangée (cache Hive par module, profil dans `user_box`).
- Écriture : inchangée via `OfflineQueueService`, étendu d'un type `uploadStudentCard`.
- Affichage : `SyncChip` dans l'en-tête de l'accueil ; `OfflineBanner` restylé en haut
  des listes de modules ; sur le profil, la ligne « Mode hors ligne » indique le nombre
  d'actions en attente.

## 8. Correctifs inclus dans la refonte

- `main.dart` : appeler `initializeDateFormatting('fr_FR')` avant `runApp` (plantage
  actuel de l'onglet Événements : `LocaleDataException`).
- `main.dart` : `MaterialApp.themeMode` + `darkTheme`.
- Le listener `applications` refusé par les règles (module Stage) est signalé au
  coéquipier concerné dans `docs/decisions.md`, pas corrigé ici.

## 9. Tests

- Jetons : test unitaire qui vérifie le contraste AA de chaque paire texte/fond dans les
  deux thèmes (calcul de luminance).
- Composants : un test par widget, rendu en clair et en sombre, « aucun texte < 13 px »,
  cibles ≥ 48 dp.
- Écrans : les tests existants « UI contract (gradient style) » sont remplacés par un
  contrat « hero sheet » (présence de `HeroSheetScaffold`, pas de `GradientScaffold`,
  bouton primaire orange, erreurs en `danger`). Les tests fonctionnels (validation,
  navigation, OTP, export, suppression…) sont conservés tels quels.
- Adaptatif : accueil et profil rendus à 360 × 640, 412 × 915 et 800 × 1280 sans
  débordement, avec `textScaler` 1.0 et 1.3.
- Nouveaux flux : onboarding (affiché une fois), envoi de carte (en ligne, hors ligne mis
  en file puis rejoué), revue admin (valider, refuser avec motif), changement de rôle,
  `UserStatsService.aggregate` (périodes, variation, répartition), `ThemeProvider`
  (persistance).
- Règles : tests `@firebase/rules-unit-testing` pour `studentCard` et `disabled`
  (dossier `test/rules/`, exécutés contre l'émulateur ; documentés dans le README).
- Vérification visuelle : chaque écran capturé sur l'émulateur Pixel 8 en clair et en
  sombre, rangé dans `docs/screenshots/`.

## 10. Ordre de livraison

1. Jetons, thèmes clair/sombre, `ThemeProvider`, composants partagés, galerie de
   composants (écran de debug `DesignGalleryScreen`, accessible depuis le profil en mode
   debug). Tests de composants. `fl_chart` et `shared_preferences` ajoutés.
2. `AppShell` + `FloatingNavBar`, correctif `fr_FR`, onboarding, accueil visiteur.
3. Authentification (cinq écrans) et réécriture des tests de contrat.
4. Accueil connecté avec graphiques.
5. Profil, modifier le profil (filière), thème, carte étudiant côté étudiant, file
   hors ligne étendue, modèle et règles.
6. Administration : utilisateurs et rôles, revue des cartes, statistiques.
7. Captures clair/sombre, README (table des concepts du cours mise à jour, comptes de
   test), `docs/decisions.md`.

Chaque étape : `flutter analyze` sans avertissement, tests verts, vérification sur
l'émulateur, commit sur `nouvelle-ui`.

## 11. Hors périmètre

Écrans des modules Vente & Don, Annonces, Événements, Stage & Emploi (au-delà de
l'héritage du thème) ; notifications push ; OCR ; sélection de campus ; mode tablette
paysage dédié ; iOS (pas de Xcode sur la machine).
