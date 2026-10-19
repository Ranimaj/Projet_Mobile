# Module Événements (P4) — scénarios de test

Branche `evenement`. Tableau à remplir pendant la recette sur émulateur (**OK / KO**).

## Résultats automatiques (au moment de la remise)

| Vérification | Résultat |
|---|---|
| `flutter analyze` | **No issues found** |
| `flutter test test/evenements` | **349 / 349** tests réussis |
| `flutter test` (projet complet) | 349 réussis, **1 échec** : `test/widget_test.dart` (test d'équipe qui démarre toute l'app sans Firebase ; existait avant le module, hors périmètre) |
| `flutter build apk --debug` | **Compile** |

Les tests du module sont dans `test/evenements/` ; ils n'ont besoin ni de Firebase, ni du réseau, ni d'un téléphone (`MockClient` remplace les API, l'heure est passée en paramètre).
Abréviation : `tests/X › groupe › test` = fichier `test/evenements/X_test.dart`, groupe, nom du test.

## Préparation commune

- Deux comptes : **A** (organisateur) et **B** (étudiant), sur deux émulateurs ou un émulateur + un téléphone.
- Position de l'émulateur : **⋯ → Extended controls → Location** → « Tunis » → *Set location*.
- Règles Firestore v5 **déployées** (par la personne qui déploie) pour tout ce qui teste un refus du serveur. Sans déploiement, seuls les contrôles de l'app s'appliquent ; les règles se testent alors dans le **Rules Playground** (cas donnés aux étapes 2, 6, 6b, 10, 12, 13).
- Mode avion : panneau rapide de l'émulateur.

## Scénarios

| # | Scénario | Résultat attendu | Test automatique | Étapes manuelles (si « manuel ») | OK/KO |
|---|---|---|---|---|---|
| 1 | Créer avec un titre vide | Erreur sous le champ « Titre requis (3 à 80 caractères) », rien n'est enregistré | `tests/event_validators › titre › vide ou null` ; `… › espaces seulement` | + → laisser le titre vide → **Créer** → erreur sous le titre, aucun document dans Firestore | |
| 2 | Créer un événement qui commence dans 5 min | Refusé : « Le début doit être dans au moins 15 minutes. » | `tests/event_validators › début › dans 5 min : refusé` ; `… › exactement 15 min : accepté ; 14 min : refusé` | Début = aujourd'hui, heure + 5 min → erreur sous « Début » | |
| 3 | Fin avant le début | Refusé : « La fin doit être après le début (15 min à 72 h) » | `tests/event_validators › fin › avant le début : refusé` ; `… › égale au début : refusé` | Fin = même jour, heure plus tôt → erreur sous « Fin » | |
| 4 | Capacité 0, 5001 ou « abc » | Refusé (« Entre 1 et 5000 ») ; les lettres ne peuvent pas être saisies | `tests/event_validators › capacité › 0 et 5001 refusés ; 1 et 5000 acceptés` ; `… › pas un entier refusé` | Taper 0, puis 5001 → erreur ; essayer des lettres → impossibles (clavier numérique) | |
| 5 | Créer deux fois le même événement | Le second est refusé : « Vous avez déjà créé cet événement à cette date » | `tests/event_validators › doublon › même titre avec casse et espaces différents : refusé` | Créer « Soirée Jazz » demain 20 h, puis « soirée   JAZZ » même date → message | |
| 6 | Créer un événement valide | Visible dans la liste et dans Firestore avec tous les champs v2 | `tests/event_model › toMap / fromMap aller-retour › tous les champs v2 sont conservés` (partiel) | Créer → l'événement apparaît ; console : `endDate`, `capacity`, `price`, `status`, `checkedInUserIds`, `paidUserIds`, `createdAt`, `updatedAt` | |
| 7 | S'inscrire / se désinscrire | Le bouton et le compteur changent tout de suite, sur les deux comptes | **Manuel** (flux en direct) ; logique : `tests/event_model › copyWith / copyWithRegistration › inscription : ajoute…` | A et B ouvrent le même événement ; B touche **S'inscrire** → sans rien toucher, A voit « 1 / N inscrits » ; B se désinscrit → A voit le compteur baisser | |
| 8 | S'inscrire quand c'est complet | Bouton gris « Complet » + raison | `tests/event_rules › registrationBlocked › complet` ; `tests/event_rules › jauge des places › complet : ratio 1, 0 place` | Capacité 1, B inscrit → C ouvre → bouton « Complet » désactivé | |
| 9 | Deux comptes pour la dernière place en même temps | Une seule inscription réussit | **Manuel** (transaction Firestore, impossible sans serveur) | Capacité 1, personne d'inscrit. C ouvre l'événement. Dans la console, ajouter `"x"` à `registeredUserIds`. C touche **S'inscrire** → « Complet… », la liste se recharge, la console ne contient que `x` | |
| 10 | Événements qui se chevauchent | Avertissement « Conflit d'horaire avec « X ». S'inscrire quand même ? » | `tests/event_rules › conflit d’horaire ›` 6 tests (dont « bout à bout (16 h / 16 h) : pas de conflit ») | S'inscrire à A (14 h–16 h) puis à B (15 h–17 h) → boîte de dialogue ; **Annuler** ne fait rien | |
| 11 | Modifier le titre alors que quelqu'un est inscrit | Les inscriptions sont conservées (seul `title` + `updatedAt` envoyés) | `tests/event_model › changedFieldsSince › seul le titre change → seul le titre est envoyé` ; `… › jamais les inscriptions, le statut ni l’organisateur` | B inscrit ; A ⋮ → Modifier → titre → enregistrer → console : B toujours dans `registeredUserIds` | |
| 12 | Baisser la capacité sous le nombre d'inscrits | Refusé : « Entre 1 et 5000 (minimum : N inscrits) » | `tests/event_validators › capacité › modification : pas sous le nombre d’inscrits` | 2 inscrits, capacité 3 → Modifier → capacité 1 → erreur | |
| 13 | Annuler avec un motif | Badge rouge « ANNULÉ », inscription désactivée, caché de « À venir » | `tests/event_rules › suppression et annulation › motif : 5 à 200 caractères` ; `tests/event_model › statusAt › annulé gagne sur tout…` ; `tests/event_rules › filtres combinés › À venir : sans annulés ni terminés…` | ⋮ → Annuler l'événement → « Non » refusé, « Salle indisponible » → bandeau rouge, bouton gris, absent de À venir, visible dans Mes événements | |
| 14 | Supprimer un événement avec des inscrits | Refusé, et « Annuler l'événement » proposé | `tests/event_rules › suppression et annulation › organisateur, avec inscrits : refusée, annulation proposée` ; `… › admin, avec inscrits : autorisée (modération)` | 1 inscrit → ⋮ → Supprimer → « Impossible de supprimer : 1 inscrit(s)… » + bouton Annuler l'événement | |
| 15 | Un autre utilisateur essaie de modifier / annuler | Pas de menu ⋮ ; une écriture directe est refusée par les règles | `tests/attendees_rules › canManageAttendees ›` 5 tests ; serveur : **Playground** (étape 2 cas D1, étape 6b cas E3) | B ouvre l'événement de A → pas de ⋮ ; Playground : `update` par `etudiantB` sur `title` → refusé | |
| 16 | Mode avion : consulter | Événements en cache affichés + bandeau hors-ligne | **Manuel** (cache Hive) | Ouvrir la liste en ligne, puis mode avion, fermer/rouvrir l'onglet → liste affichée, bandeau orange | |
| 17 | Mode avion : s'inscrire à un événement avec capacité | « Connexion requise : places limitées. » rien en file d'attente | **Manuel** (provider + plugin connectivité) | Mode avion → S'inscrire → message ; compteur d'actions en attente inchangé | |
| 18 | Événement terminé | Dans « Passés », en lecture seule | `tests/event_rules › filtres combinés › Passés : seulement les terminés non annulés` ; `tests/event_validators › modification bloquée › terminé : refusé` | Onglet Passés → l'événement ; ⋮ → Modifier → « Un événement terminé ne peut plus être modifié. » | |
| 19 | Recherche « ecole » trouve « École » | Correspondance sans accents | `tests/event_rules › recherche › « ecole » trouve « École » (lieu)` | 🔍 → « ecole » → l'événement à « École … » apparaît | |
| 20 | Filtre + jour sans résultat | Message propre au filtre | `tests/event_rules › filtres combinés › aucun résultat : liste vide` (le texte du message : manuel) | Catégorie « Carrière » + un jour vide → « Aucun événement ce jour. » + « Voir tous les événements » | |
| 21 | Validation du prix | Virgule acceptée, 3 décimales / négatif / > 1000 / texte refusés | `tests/event_validators › prix ›` 8 tests (virgule, 3 décimales, négatif, 1000.01, texte, arrondi) | Prix « 12,5 » → accepté (12,50 TND) ; « 12,505 », « 1000,01 » → erreur ; lettres impossibles | |
| 22 | Ancienne catégorie (Job Fair) | Affichée « Carrière », toujours modifiable | `tests/event_categories_price › catégories… › anciennes valeurs traduites` ; `… › fromMap applique la traduction (aucune migration)` ; serveur : **Playground** étape 13 cas A2 / D2 | Console : catégorie d'un événement = `Job Fair` → l'app montre CARRIÈRE ; Modifier le titre seulement → enregistré, la console garde `Job Fair` | |
| 23 | Autocomplétion du lieu | Suggestion choisie → carte ; texte libre → pas de carte | `tests/photon_service ›` 14 tests (dont « [lng, lat] remis dans l’ordre lat, lng », « seulement la Tunisie… ») ; `tests/event_rules › lieu modifié ?` | Taper « ariana » → choisir une suggestion → ✓ vert → créer → fiche avec carte ; refaire avec « Salle B12 » sans choisir → « Lieu non localisé » | |
| 24 | Affiche | JPG/PNG valides acceptés ; > 5 Mo, faux fichier refusés ; échec d'envoi → boîte de dialogue | `tests/poster ›` validate (6 tests), dimensions, URL autorisée, `CloudinaryService` (7 tests) | Photo normale → aperçu + taille → Créer → affiche dans l'en-tête, la grande carte et la vignette ; image 6 Mo → refus ; .gif → refus ; mode avion juste avant Créer → « Envoi de l'affiche impossible » (Réessayer / Enregistrer sans affiche / Annuler) | |
| 25 | Liste des participants | Présent, payé, filtres ; une désinscription nettoie les listes | `tests/attendees_rules ›` canMarkPresent (6), canMarkPaid (5), attendeeStats (4), filterAttendees (7), « désinscription : retiré aussi des présents et des payés » | A ⋮ → Participants : pointer B Présent, C Payé → résumé et recette ; filtres Présents / Absents / Non payés ; C se désinscrit → disparaît, recette baisse | |
| 26 | Billet QR et scanner | Billet avec puces en direct ; verdicts du scan | `tests/ticket_rules ›` QR (7), accès (4), puces (2), partage (3), verdict (7) ; `tests/ticket_screen ›` 4 tests widget | B : Mon billet → QR + « À payer sur place » ; A : Participants → 📷 Scanner le billet de B → « Présent : … », puis « Déjà pointé » ; QR quelconque → « Billet invalide » | |
| 27 | Tri « Près de moi » | Tri par distance + distance affichée ; refus → message + tri par date | `tests/near_me ›` haversine (6), tri (4), 3 tests widget (distance affichée) | ⚙ → Trier par → Près de moi → autoriser → distances ; refuser la permission → message + date ; localisation coupée → « Ouvrir les réglages » | |
| 28 | Puce météo | Affichée si localisé et < 14 jours ; cachée hors-ligne / au-delà | `tests/open_meteo_service ›` 10 tests service, `WeatherRules.describe` (4), `shouldShowWeather` (4) | Événement localisé dans 2 jours → puce « 19 °C · … » ; mode avion → pas de puce, pas d'erreur ; dans 20 jours → pas de puce | |
| 29 | Erreurs d'itinéraire | Refusé / localisation coupée / hors-ligne : message clair, Google Maps toujours possible | `tests/osrm_service ›` 9 tests ; `tests/itinerary_rules ›` 7 tests (lien Google Maps inclus) | Itinéraire : refuser la permission → message + Réessayer ; refuser deux fois → « Ouvrir les réglages » ; localisation coupée → « Activer la localisation » ; mode avion → « Itinéraire indisponible hors ligne » ; « Ouvrir dans Google Maps » marche dans tous les cas | |

## Ce que les tests automatiques ne peuvent pas prouver

Ces points dépendent d'un vrai serveur, d'un plugin natif ou du matériel ; ils ne se vérifient qu'à la main (ou dans le Rules Playground) :

- **Règles Firestore** (toutes versions) : aucun émulateur Firebase dans le projet ; vérifiées par les cas du Rules Playground, pas par `flutter test`.
- **Temps réel** (scénario 7, 25 en direct) : `snapshots()` nécessite Firestore.
- **Transaction de la dernière place** (9).
- **Cache hors-ligne Hive** et file d'attente (16, 17) : nécessitent l'app lancée.
- **Plugins natifs** : calendrier (`add_2_calendar`), caméra / scan (`mobile_scanner`), galerie et compression (`image_picker`, `flutter_image_compress`), GPS et permissions (`geolocator`), partage (`share_plus`), ouverture de Google Maps (`url_launcher`).
- **Vrais serveurs** Photon, OSRM, Open-Meteo, Cloudinary : seulement simulés par `MockClient` ; le preset Cloudinary `campusconnect_events` doit exister et être *unsigned*.
- **Textes affichés** dans certains états (messages vides propres au filtre) : la logique est testée, la phrase exacte se vérifie à l'écran.
