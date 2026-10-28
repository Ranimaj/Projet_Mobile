# Décisions de conception — nouvelle UI

Ce document consigne les choix faits pendant la refonte de l'interface
(branche `nouvelle-ui`) et leurs limites connues.

## 1. Palette orange au lieu du violet du cahier des charges

Le cahier des charges prévoyait une palette violette. La refonte adopte un orange
de marque, choix assumé par le propriétaire du projet. La couleur primaire est
légèrement assombrie (`#F9671E` en clair, `#EC7136` en sombre) pour que le texte
blanc atteigne un contraste de 3:1 ; les dégradés des héros gardent les valeurs d'origine.

## 2. OCR abandonné : revue admin des cartes et gestion des rôles dans l'app

La lecture automatique de la carte étudiante (OCR) est abandonnée. Elle est remplacée
par une soumission de la photo de carte, une revue par un administrateur (écran
« Cartes à vérifier ») et une gestion des rôles directement dans l'app (écran
« Utilisateurs »). Risque accepté : la vérification repose sur le jugement humain
de l'administrateur, qui peut valider une carte à tort (risque sur le grade du compte).

## 3. Navigation : 5 éléments flottants et avatar pour le profil

La barre flottante porte 5 entrées (Accueil, Vente & Don, Annonces, Événements, Stages).
Le profil n'est pas un onglet : il s'ouvre par l'avatar en haut de l'accueil.

## 4. Thème : suit le système, avec surcharge dans l'app

Le mode par défaut est « Système ». La ligne « Thème » du profil permet de forcer
« Clair » ou « Sombre ». Le choix est mémorisé (`shared_preferences`).

## 5. Filières en liste déroulante et campus unique

La filière (département) se choisit dans une liste fermée, ce qui évite les
saisies libres et facilite les statistiques et le ciblage. Un seul campus est géré :
`ESPRIT Ghazela`.

## 6. Images de remplacement générées localement

Aucun téléchargement n'a été fait. Les visuels sont des images abstraites générées
localement (`tool/gen_placeholder_images.py`, `tool/gen_cover_image.py`). L'équipe doit
remplacer `assets/images/cover_campus.jpg` et le héros du visiteur (`campus_2.jpg`)
par de vraies photos. L'onboarding utilise déjà les vraies photos ESPRIT de
l'utilisateur (commit en attente). Quand `assets/images/onboarding/esprit_campus.jpg`
sera versionnée, le héros visiteur pourra l'utiliser en changeant une seule ligne
(`lib/screens/visitor/visitor_home_screen.dart`, ligne 249) ; ce changement n'a pas été
fait ici car l'image appartient à un commit en attente.

## 7. `studentCard` n'est pas un champ de profil éditable

`UserModel.toEditableMap` n'envoie jamais `studentCard`. Seule la soumission de carte
l'écrit, en remplaçant la map entière (`update({'studentCard': {...}})`, pas un merge).
Raison liée aux règles Firestore : la règle de mise à jour par le propriétaire n'accepte
que certaines formes ; en remplaçant la map entière, les anciennes clés
(`reviewedBy`, `reviewedAt`, `rejectReason`) disparaissent et la nouvelle soumission
après un refus passe la règle (test « resubmit after rejection »).

## 8. File d'attente hors-ligne des cartes étudiantes

Les soumissions de carte faites hors-ligne sont stockées dans une file Hive
(`uploadStudentCard`). La photo est copiée localement (`path_provider`) sous un nom de
fichier relatif unique ; seul ce nom relatif est stocké, car le dossier de l'app peut
changer d'un lancement à l'autre. La file est rejouée par utilisateur (une action ne
s'exécute que pour son propriétaire) dès le retour du réseau, et purgée à la
déconnexion (les copies locales sont supprimées).

## 9. Garde-fous admin et risques résiduels

Le dernier administrateur actif ne peut être ni rétrogradé ni désactivé. Deux risques
résiduels sont documentés :

- **Rétrogradation mutuelle** : deux admins qui se rétrogradent en même temps peuvent
  laisser l'app sans admin. Une transaction client ne peut pas compter les admins ;
  il faudrait une Cloud Function. Dépannage : corriger le rôle dans la console.
- **`disabled` appliqué côté client** : le champ n'est contrôlé qu'aux changements d'état
  d'authentification, les règles Firestore ne le lisent pas. Pour le renforcer, ajouter
  `!isDisabled()` (lecture de `users/{uid}.disabled`) à la règle `update` de `users`
  et aux règles d'écriture de chaque module.

## 10. Notifications push hors périmètre

Les notifications push exigent des Cloud Functions, donc le plan Blaze. Le projet
reste sur le plan Spark : hors périmètre.

## 11. Règle `applications` : écoute refusée pour Stage & Emploi

L'écoute de la collection `applications` est refusée par `firestore.rules`
(`PERMISSION_DENIED`, « Property candidateId is undefined » dans les journaux) : la requête
demande toutes les candidatures alors que la règle n'autorise que la lecture des siennes.
Le responsable du module Stage & Emploi doit filtrer par `candidateId` ou `recruiterId`.

## 12. Statistiques sur le plan Spark

Sans Cloud Function ni agrégats côté serveur, l'écran de statistiques admin lit toute
la collection `users` côté client. Acceptable pour un campus de démonstration ; à
remplacer par des compteurs agrégés si le volume augmente.

## Points mineurs différés

**Design system (tâches 1 à 5)**
- Contraste : texte `textSecondary` sur `surfaceMuted` (~4:1 en clair), `labelLarge` 14 w600 sur primaire à 3:1 (règle du grand texte) et texte du chip sélectionné non vérifiés ; la spec devrait énoncer ce compromis.
- `ThemeProvider.setMode` notifie avant la fin de l'écriture (erreur non gérée) ; pas de test du cas « mode inchangé ».
- Éléments `GestureDetector` sans ripple (bouton rond, chip de filtre, avatar) ; `InitialsAvatar` sans `FittedBox`, badge sans sémantique, cas photo non testé.
- Tests manquants : bordure/désactivé de `FilterChipPill`, `SkeletonBox`, `StatTile`, pilule ghost désactivée, ordre des imports.
- Zone de recouvrement de 28 dp de la feuille non cliquable ; ripple de `PhotoCard` sous l'image ; titre/méta de `FeaturedCard` se chevauchent sur 2 lignes ou grande échelle de texte ; heuristique de séparateur de `SectionCard` fausse pour les lignes à retour ; indentation 60 de `SettingRow` codée en dur ; hauteur du héros non animée.
- Graphiques : pas de `Semantics` ; `disableAnimations`, valeurs toutes nulles, point unique, pas des libellés et callback d'infobulle non testés ; boîte de valeur de `HBarChart` (36 dp) déborde à 4 chiffres ; `DonutChart` sans garde contre les valeurs négatives ; infobulle sans bordure ; `interval: 1` construit un titre par point ; galerie non protégée par `kDebugMode` et non reliée à une route ; `bodySmall` absent.

**Navigation et coquille (tâche 6)**
- Test de padding en `>=` et seulement sur l'onglet Accueil ; pas de test du retour ; état de chargement du profil sans bouton retour ; double appui sur `_openProfile` ; `initialIndex` non borné ; titre du profil non `Expanded`.

**Onboarding et visiteur (tâches 7 et 8)**
- Titre et sous-titre changent brutalement (`AnimatedSwitcher`, `liveRegion`) ; points sans sémantique ; `cacheWidth` des `Image.asset` ovales.
- `_Events` réutilise `_Rail` avec un hack de texte vide ; cartes article avec chip Vente/Don et Gratuit/prix redondants ; cartes article et offre non cliquables alors que les cartes événement le sont ; test grand écran n'assertant que `left >=` ; test de petit texte en double ; hauteur `_railHeight` à nombre magique (`scale(88)`) ; marge de la barre sur-mise à l'échelle ; méta de `FeaturedCard` tronquée au lieu de passer à la ligne.

**Authentification (tâches 9 et 10)**
- Cinq blocs bouton retour copiés-collés ; tests « no GradientScaffold » sans assertion ; `expectNoSmallText` ignore `FittedBox` et `RichText` ; échelle de texte 1,3 pouvant chevaucher dans le héros non compact (non vérifié) ; état OTP désactivé qui paraît actif ; bordure focus désactivé ; `AppColors.auth*` code mort.
- `AuthHero.compactOf` duplique la règle compacte du scaffold ; `AuthCompactNote` s'insère avec un saut à la première frame du clavier.

**Accueil (tâches 11 et 12)**
- Helpers de taille de rails/cartes dupliqués depuis l'accueil visiteur ; ratio de la grille non testé à l'échelle 2,0 ; `_relative` utilise `_now` ; points en `outline` peu contrastés et sans sémantique ; littéral `ESPRIT Ghazela` ; état combiné hors-ligne + en attente non asserté.
- Garde `_registering` globale à l'écran : un appui sur l'autre CTA est ignoré pendant une inscription en cours, sans retour visuel.

**Modèle et règles (tâche 13)**
- `StudentCard.fromMap` avec casts implicites et `_parseDate` partagé entre classes ; règle Storage des cartes sans garde de ressource nulle (le propriétaire ne peut pas supprimer l'image) ; valeurs par défaut implicites de `auth_service`.

**Édition du profil (tâche 14)**
- `dart format` réorganise deux fichiers ; icône préfixe et libellé sémantique du menu déroulant ; bouton « Ajouter » à 46 dp et tailles littérales dans `edit_profile`.

**Profil (tâche 15)**
- Chip de la ligne d'avatar non `Flexible` à grande échelle ; nom long sans `maxLines` ; viewport de test 420×2600 masquant les problèmes sous la ligne de flottaison ; ordre des imports ; tests de chevauchement ne vérifiant pas la position sous le haut du héros ; avatar chevauchant le bouton retour quand le héros passe à 120 dp ; titre du groupe confidentialité non asserté.

**Carte étudiante et file hors-ligne (tâche 16)**
- Le rejeu peut écraser une carte déjà décidée par un admin avec `pending` ; `pendingCardQueued` avale toutes les erreurs et désérialise la boîte à chaque build, sans rafraîchissement après synchro en arrière-plan ; un `isOnline` périmé ne bascule pas vers la file ; image héros `Image.file` sans libellé sémantique.
- `deleteAccount` ne purge pas les actions de carte en file ; deux envois dans la même milliseconde partagent un nom de fichier ; câblage déconnexion → `discardQueued` et uid de `ConnectivityProvider` non testés.

**Administration (tâches 17 et 18)**
- « Refuser » utilise `PillStyle.danger` au lieu de ghost ; « Voir la carte » aussi pour les cartes refusées/vérifiées avec image (nom de test trompeur) ; snack « désactivé » programmé depuis `build` pouvant s'afficher deux fois ; `initialCardFilter` appliqué après la frame ; `reviewCard` lit puis écrit hors transaction ; statistiques sans état d'erreur et « − 0 % » ; `Colors.transparent` littéral ; liste filtrée recalculée à chaque build.
