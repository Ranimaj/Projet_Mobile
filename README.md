# CampusConnect 📱

Application mobile Flutter pour étudiants — plateforme tout-en-un du campus,
**offline-first**, construite autour de 5 gestions réparties équitablement
entre les 5 membres de l'équipe :

| Module | Responsable | CRUD | Fonctionnalités avancées | API dédiée |
|---|---|---|---|---|
| Gestion Utilisateurs | Membre 1 | Profil, inscription, rôles | Authentification biométrique (`local_auth`) + Connexion Google | Firebase Authentication + Google ML Kit |
| Gestion Vente & Don | Membre 2 | Articles (créer/lire/modifier/supprimer, réserver, terminer) | Upload multi-images compressées + recherche/filtres avancés | Cloud Firestore + Firebase Storage |
| Gestion Annonces | Membre 3 | Annonces (créer/lire/modifier/supprimer) | Notifications push ciblées par filière/année + épinglage auto des annonces officielles | Firebase Cloud Messaging |
| Gestion Événements | Membre 4 | Événements (créer/lire/modifier/annuler/supprimer, inscription atomique, présences/paiements) | Calendrier natif + vue mois, carte et itinéraire, météo, affiches, billet QR + scanner, « Près de moi » | add_2_calendar, Photon, OSRM, Open-Meteo, Cloudinary (voir [Événements (P4)](#9-événements-p4)) |
| Gestion Stage & Emploi | Membre 5 | Offres + candidatures (créer/lire/modifier/supprimer) | Matching intelligent par compétences + suivi de statut en temps réel | Firestore (candidatures en temps réel) |

Toute l'application fonctionne **hors-ligne** : consultation depuis le cache
local (Hive), actions mises en file d'attente puis synchronisées
automatiquement au retour du réseau (voir [Architecture offline](#architecture-offline-first)).

---

## 1. Prérequis

- Flutter SDK ≥ 3.22 (Dart ≥ 3.3) — `flutter --version`
- Un compte Firebase (gratuit) et le CLI FlutterFire
- Android Studio / Xcode pour les émulateurs, ou un téléphone physique

```bash
dart pub global activate flutterfire_cli
npm install -g firebase-tools   # ou: curl -sL https://firebase.tools | bash
firebase login
```

## 2. Installation

```bash
flutter pub get
```

## 3. Configuration Firebase

Le fichier `lib/firebase_options.dart` fourni est un **placeholder** — il doit
être régénéré pour votre propre projet Firebase :

```bash
firebase projects:create campusconnect-esprit   # ou utilisez un projet existant
flutterfire configure
```

Suivez les invites (sélection du projet, des plateformes Android/iOS/Web).
Cela remplace automatiquement `lib/firebase_options.dart` par vos vraies clés.

Dans la [console Firebase](https://console.firebase.google.com/), activez :

1. **Authentication** → méthodes "E-mail/mot de passe" et "Google"
2. **Cloud Firestore** → créer la base en mode production
3. **Storage** → créer le bucket par défaut
4. **Cloud Messaging** → aucune activation manuelle nécessaire

### Règles de sécurité Firestore

Déployez le fichier `firestore.rules` fourni à la racine du projet :

```bash
firebase deploy --only firestore:rules
```

Logique résumée : lecture publique sur les articles/annonces/événements/offres
(mode visiteur), écriture réservée aux auteurs authentifiés, modération et
épinglage réservés au rôle `admin`, candidatures visibles uniquement par leur
auteur, le recruteur concerné et les admins.

### Index Firestore recommandés

Pour les requêtes triées (annonces épinglées, événements à venir), Firestore
vous proposera automatiquement un lien de création d'index composite dans les
logs au premier lancement — cliquez-le, ou créez-les manuellement dans
Firestore → Index.

## 4. Lancer l'application

```bash
flutter run
```

Au premier lancement, l'app démarre en **mode visiteur** (lecture seule avec
aperçus des 4 modules) — créez un compte ou connectez-vous pour débloquer la
publication, les favoris, les inscriptions et les candidatures.

Pour créer un compte **admin** (modération des annonces) ou **recruteur**
(publication d'offres), modifiez manuellement le champ `role` du document
utilisateur correspondant dans la console Firestore (`student` → `admin` /
`recruiter`).

## 5. Architecture offline-first

- **Hive** (`lib/core/utils/local_cache_service.dart`) met en cache chaque
  collection lue depuis Firestore, pour un affichage instantané hors-ligne.
- **File d'attente** (`lib/core/utils/offline_queue_service.dart`) : toute
  création/modification/suppression faite hors-ligne est enregistrée
  localement et rejouée automatiquement dès la reconnexion
  (`ConnectivityProvider._syncPendingActions()`).
- **`FirestoreRepository<T>`** (`lib/services/firestore_repository.dart`) est
  le cœur générique réutilisé par les 4 providers de modules (articles,
  annonces, événements, offres) : il centralise la logique
  Firestore ↔ cache ↔ file d'attente pour éviter toute duplication de code.
- Un bandeau orange (`OfflineBanner`) informe l'utilisateur du mode
  hors-ligne et du nombre d'actions en attente de synchronisation.

## 6. Structure du projet

```
lib/
├── core/            # thème (couleurs/typographie), constantes, services utilitaires
├── models/          # modèles de données (User, Article, Annonce, Event, JobOffer...)
├── services/        # Auth, Storage, Notifications, FirestoreRepository générique
├── providers/        # état applicatif (Provider/ChangeNotifier) par module
├── widgets/         # composants partagés (boutons, badges, bandeau offline...)
└── screens/
    ├── auth/        # connexion, inscription
    ├── visitor/     # accueil visiteur non connecté
    ├── home/        # coquille de navigation + accueil connecté
    ├── profile/     # profil, RGPD, sécurité
    ├── vente_don/   # Gestion Vente & Don
    ├── annonces/    # Gestion Annonces
    ├── evenements/  # Gestion Événements
    └── stages_emploi/ # Gestion Stage & Emploi
```

## 7. Design system

Polices **Outfit** (titres) et **Inter** (texte courant) via `google_fonts`,
palette indigo/violet/orange définie dans `lib/core/theme/app_colors.dart`,
cartes arrondies (16 px) avec ombres douces — cohérent avec les maquettes
validées du projet.

## 8. Builder pour la remise (APK de démonstration)

```bash
flutter build apk --release
# L'APK se trouve dans build/app/outputs/flutter-apk/app-release.apk
```

## 9. Événements (P4)

Module réalisé sur la branche `evenement`. Scénarios de recette :
[`docs/EVENEMENT_TESTS.md`](docs/EVENEMENT_TESTS.md) · préparation de la
soutenance : [`docs/EVENEMENT_DEFENSE.md`](docs/EVENEMENT_DEFENSE.md).

### Fonctionnalités et écrans

| Écran | Fichier | Contenu |
|---|---|---|
| Liste | `evenements_list_screen.dart` | Onglets *À venir / Passés / Mes inscriptions / Mes événements* (`TabBar` ; les deux derniers une fois connecté), bande des jours, carte « Prochain événement », recherche sans accents, filtres (catégorie, gratuit/payant), tri *Date / Près de moi* |
| Calendrier | `event_calendar_screen.dart` | Grille du mois (`GridView.builder`) avec un point par jour occupé |
| Détail | `event_detail_screen.dart` | Mis à jour en direct (`StreamBuilder`), affiche, places restantes, conflit d'horaire, météo, carte, ajout au calendrier, partage, menu organisateur |
| Créer / modifier | `add_event_screen.dart` | `Form` + validateurs, lieu avec autocomplétion, affiche, capacité, prix ; création possible hors-ligne |
| Itinéraire | `event_map.dart` | Carte OSM, trajet à pied/voiture (OSRM), lien Google Maps |
| Participants | `attendees_screen.dart` | Liste des inscrits, pointage *Présent* / *Payé*, filtres, recette |
| Mon billet | `ticket_screen.dart` | QR code (`eventId` + `uid`), statut présent/payé en direct |
| Scanner | `scan_ticket_screen.dart` | Lecture du billet par l'organisateur, pointage automatique |

Règles métier (sans Flutter, testées) : `event_rules.dart`,
`event_validators.dart`, `ticket_rules.dart`, `poster_rules.dart`,
`place_rules.dart`, `itinerary_rules.dart`, `weather_rules.dart`,
`event_calendar_sync.dart`, `event_categories.dart`.

### API gratuites et limites

Aucune clé payante, aucune carte bancaire. Chaque service renvoie un résultat
typé (succès / erreur) et n'empêche jamais l'écran de s'afficher.

| Service | Usage | Limites respectées dans l'app |
|---|---|---|
| **Photon** (photon.komoot.io) | Autocomplétion du lieu | Pause de 500 ms après la frappe, 1 requête / 500 ms max, délai 8 s, résultats limités à la Tunisie, 5 suggestions, cache en mémoire |
| **OSRM** (router.project-osrm.org) | Durée et tracé de l'itinéraire | Serveur de démonstration : 1 requête / s, délai 10 s, pas de garantie de disponibilité → Google Maps reste proposé |
| **Open-Meteo** | Puce météo | Prévisions sur 14 jours seulement, délai 10 s, cache en mémoire, cachée hors-ligne |
| **Cloudinary** (envoi *unsigned*) | Affiches | Seulement le *cloud name* et le *preset* dans l'app (pas de secret). Image ≤ 5 Mo avant compression, JPEG/PNG, 1600 px max, EXIF supprimé. **Limite** : un envoi unsigned ne peut pas supprimer l'image (il faudrait un serveur) |
| **flutter_map + tuiles OSM** | Cartes | Usage raisonnable (politique OSM), `User-Agent` de l'app, pas de mode hors-ligne pour les tuiles |
| **Google Maps** (lien `url_launcher`) | Navigation | Simple URL publique, aucune clé |

### Règles hors-ligne

- **Consultation** : la liste vient du cache Hive ; bandeau orange.
- **Création / modification / annulation** : envoyées tout de suite si
  possible, sinon **mises en file d'attente** (seulement pour une absence de
  réseau ou `unavailable`, jamais pour un refus `permission-denied`). Un
  identifiant fixé à l'avance évite les doublons au renvoi.
- **Inscription** : **connexion obligatoire** (transaction Firestore pour ne
  pas dépasser la capacité).
- **Affiche, météo, itinéraire, autocomplétion** : désactivés hors-ligne, avec
  un message.

### Règles Firestore (bloc `events` de `firestore.rules`)

- Lecture publique (mode visiteur).
- **Création** : utilisateur connecté, `organizerId` = lui-même, contenu valide
  (titre 3–80, description 10–1000, lieu 3–100, catégorie connue, fin après le
  début et ≤ 72 h, capacité 1–5000, prix 0–1000, affiche venant de notre cloud
  Cloudinary), début dans le futur selon l'**heure du serveur**, listes vides.
- **Modification** par l'organisateur ou un admin : jamais `organizerId`,
  `createdAt`, ni les présences ; capacité ≥ inscrits ; un événement annulé ne
  redevient pas actif ; l'annulation seule (4 champs) reste possible pour un
  ancien document.
- **Inscription** : chacun ajoute ou retire **uniquement son propre uid**,
  avant le début, dans la limite des places.
- **Présences / paiements** : organisateur ou admin, une personne inscrite à la
  fois ; « payé » seulement si l'événement est payant.
- **Suppression** : organisateur sans inscrits, ou admin.

Tester : console Firebase → Firestore → **Règles** → **Rules Playground**
(simuler `update` sur `/events/{id}` avec un uid et des données). Le fichier
n'est **pas déployé** par ce module ; le déploiement se fait par la personne
responsable (`firebase deploy --only firestore:rules`).

### Rôles

| Action | Visiteur | Étudiant | Organisateur (son événement) | Admin |
|---|:-:|:-:|:-:|:-:|
| Voir la liste / le détail | ✅ | ✅ | ✅ | ✅ |
| Créer un événement | ❌ | ✅ | ✅ | ✅ |
| S'inscrire / se désinscrire | ❌ | ✅ | ✅ | ✅ |
| Mon billet | ❌ | ✅ (si inscrit) | ✅ (si inscrit) | ✅ (si inscrit) |
| Modifier / annuler | ❌ | ❌ | ✅ | ✅ |
| Participants, pointage, scanner | ❌ | ❌ | ✅ | ✅ |
| Supprimer | ❌ | ❌ | ✅ (sans inscrits) | ✅ (toujours) |

### Modèle de données (`events/{id}`)

| Champ | Type | Remarque |
|---|---|---|
| `organizerId`, `organizerName` | string | auteur, jamais modifié |
| `title`, `description`, `location` | string | 3–80 / 10–1000 / 3–100 caractères |
| `category` | string | Conférence, Carrière, Sport, Culture, Vie associative (anciennes valeurs traduites à la lecture) |
| `startDate`, `endDate` | timestamp | fin par défaut : début + 2 h |
| `latitude`, `longitude` | number? | seulement si le lieu vient d'une suggestion |
| `capacity` | int? | null = illimité |
| `price` | number? | null ou 0 = gratuit (TND, informatif) |
| `posterUrl` | string? | URL Cloudinary |
| `status` | string | `active` / `cancelled` |
| `cancelReason`, `cancelledAt` | string?, timestamp? | si annulé |
| `registeredUserIds` | string[] | inscrits |
| `checkedInUserIds`, `paidUserIds` | string[] | présents, payés (sous-ensembles des inscrits) |
| `createdAt`, `updatedAt` | timestamp | heure du téléphone (une `serverTimestamp` ne peut pas être stockée dans la file Hive) |
| `pendingSync` | bool | **local seulement** (en attente d'envoi), jamais écrit dans Firestore |

### Structure

```
lib/models/event_model.dart          # modèle, fromMap/toMap, changedFieldsSince
lib/providers/event_provider.dart    # état, Firestore, cache, file d'attente
lib/screens/evenements/              # écrans, règles métier, services API
test/evenements/                     # 15 fichiers de tests (349 tests)
docs/EVENEMENT_TESTS.md, docs/EVENEMENT_DEFENSE.md, docs/NOTE_USERS_RULES.md
```

### Fichiers partagés modifiés

| Fichier | Raison |
|---|---|
| `pubspec.yaml` / `pubspec.lock` | paquets ci-dessous |
| `android/app/src/main/AndroidManifest.xml` | `<queries>` pour l'intent calendrier ; localisation précise/approximative |
| `android/build.gradle.kts` | compileSdk 36 imposé aux plugins (correction du build) |
| `ios/Runner/Info.plist` | textes d'autorisation : calendrier, contacts, localisation, caméra, photos |
| `lib/main.dart` | `initializeDateFormatting('fr_FR')` (dates en français) |
| `lib/core/utils/local_cache_service.dart` | `toHiveSafe` : convertit les `Timestamp` avant Hive |
| `lib/core/utils/offline_queue_service.dart` | `toHiveSafe` sur les actions en attente |
| `lib/core/constants/app_constants.dart` | liste des catégories déplacée dans le module |
| `lib/services/firestore_repository.dart` | `debugPrint` dans les `catch` (pas de changement de logique) |
| `firestore.rules` | bloc `events` uniquement |

### Paquets ajoutés

| Paquet | Pourquoi |
|---|---|
| `add_2_calendar` | ajout au calendrier natif |
| `http` | appels Photon, OSRM, Open-Meteo, Cloudinary |
| `flutter_map`, `latlong2` | carte OSM sans clé Google |
| `url_launcher` | ouvrir Google Maps / les réglages |
| `qr_flutter` | dessiner le billet QR |
| `share_plus` | partager un événement |
| `mobile_scanner` | scanner les billets |

Déjà présents et réutilisés : `image_picker`, `flutter_image_compress`,
`cached_network_image`, `geolocator`, `hive`, `connectivity_plus`.

### Limites connues

- L'heure du téléphone sert aux contrôles de l'app ; seules les règles
  (`request.time`) font foi côté serveur.
- Les règles ne sont pas couvertes par des tests automatiques (pas
  d'émulateur Firebase dans le projet) : vérification au Rules Playground.
- Une affiche remplacée ou un événement supprimé laisse l'image sur
  Cloudinary (suppression impossible sans serveur).
- Le billet QR n'est pas signé : il contient l'id de l'événement et l'uid ;
  le scanner vérifie l'inscription en direct, mais un QR copié reste lisible.
- Pas de notifications (rappel, annulation) : il faudrait Cloud Functions.
- OSRM et Photon sont des serveurs publics de démonstration : ils peuvent être
  lents ou indisponibles.
- Le test d'équipe `test/widget_test.dart` échoue (il lance l'app sans
  Firebase) ; il est hors du module.

---

Projet réalisé dans le cadre du module **Développement Mobile** — ESPRIT.
