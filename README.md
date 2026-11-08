# CampusConnect 📱

Application mobile Flutter pour étudiants — plateforme tout-en-un du campus,
**offline-first**, construite autour de 5 gestions réparties équitablement
entre les 5 membres de l'équipe :

| Module | Responsable | CRUD | Fonctionnalités avancées | API dédiée |
|---|---|---|---|---|
| Gestion Utilisateurs | Membre 1 | Profil, inscription, rôles | Authentification biométrique (`local_auth`) + Connexion Google | Firebase Authentication + Google ML Kit |
| Gestion Vente & Don | Membre 2 | Articles (créer/lire/modifier/supprimer, réserver, terminer) | Upload multi-images compressées + recherche/filtres avancés | Cloud Firestore + Firebase Storage |
| Gestion Annonces | Membre 3 | Annonces (créer/lire/modifier/supprimer) | Notifications push ciblées par filière/année + épinglage auto des annonces officielles | Firebase Cloud Messaging |
| Gestion Événements | Membre 4 | Événements (créer/lire/modifier/supprimer, inscription) | Synchronisation calendrier natif + vue par date | Intégration calendrier (add_2_calendar) |
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

### En une commande

```bash
tool/run.sh emu     # émulateurs Firebase locaux : aucun compte, aucun SMS réel
tool/run.sh prod    # projet Firebase réel : Google Sign-In et vrais SMS
```

- `emu` démarre les émulateurs (Auth 9099, Firestore 8085, Storage 9199) s'ils ne tournent pas,
  puis lance l'app dessus. Les codes SMS et les liens de vérification d'email s'affichent dans
  l'UI des émulateurs (http://127.0.0.1:4000), rien n'est envoyé pour de vrai.
- `prod` lit `.env.json` (copie de `.env.example.json`) pour `GOOGLE_WEB_CLIENT_ID`,
  le client OAuth *Web* du projet (Firebase console → Authentication → Google). Ce fichier
  n'est pas versionné.

Pour Google Sign-In sur Android, l'empreinte SHA-1 de la clé de debug doit être déclarée sur
l'app Android du projet Firebase et `android/app/google-services.json` téléchargé :

```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android | grep SHA1
```

### Comptes de démonstration (émulateurs)

Avec les émulateurs lancés, `tool/seed.sh` crée (de façon idempotente) des comptes
et leurs documents `users/{uid}` :

```bash
tool/seed.sh
```

| Email | Rôle | Carte étudiante |
|---|---|---|
| `admin@esprit.tn` | admin | aucune |
| `amel@esprit.tn` | étudiant | en attente |
| `sarra@esprit.tn` | étudiant | en attente |
| `youssef@esprit.tn` | étudiant | en attente |
| `recruteur@vermeg.tn` | recruteur | aucune |

Mot de passe commun : `Campus2026!`.

### Manuellement

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

## Gestion Vente & Don

Écrans dans `lib/screens/vente_don/`, logique dans `lib/providers/article_provider.dart`
et `lib/core/utils/article_search.dart`. **La gestion n'utilise pas Firebase** : toutes
ses données sont dans une base **SQLite** sur le téléphone (voir plus bas). La connexion
et les autres modules de l'app ne changent pas.

- **CRUD** : publier (`ArticleFormScreen`), consulter (grille + détail), **modifier**
  (menu du propriétaire → « Modifier »), réserver / remettre disponible / marquer
  vendu ou donné, supprimer (avec confirmation).
- **Avancé 1 — photos** : jusqu'à 6 photos par article, copiées dans le dossier de
  l'app ; la première sert de couverture dans la grille et le détail affiche un
  carrousel. Les 4 articles de démonstration ont leurs photos dans `assets/images/demo/`.
- **Avancé 2 — recherche intelligente** : recherche sans accents ni majuscules, par début
  de mot, dans le titre, la catégorie et la description (le titre pèse le plus), combinée
  avec les filtres catégorie, gratuit, **fourchette de prix**, **rayon autour de
  l'utilisateur** (1 à 25 km, position GPS facultative) et un tri (récents, prix ↑/↓,
  plus proches, plus vus).
- **Contacter le vendeur** : messagerie dans SQLite (tables `conversations` et
  `messages`), liste « Mes messages » avec non-lus.
- **Favoris** (écran « Mes favoris »), **compteur de vues** (une vue par session, jamais
  pour le propriétaire), écran **« Mes articles »** (tous les états, vues et favoris).
- **Articles de démo** : bouton « Ajouter 4 articles de démo » (liste vide, ou ✨ dans
  « Mes articles »).
- **Sans réseau** : tout fonctionne, puisque rien ne passe par internet.
- **Tests** : `test/core/article_search_test.dart`, `test/models/article_model_test.dart`,
  `test/providers/article_provider_test.dart`, `test/services/local_article_repository_test.dart`,
  `test/services/chat_service_test.dart`, `test/ai/article_ai_logic_test.dart`,
  `test/screens/vente_don_list_screen_test.dart`, `article_detail_screen_test.dart`,
  `article_form_screen_test.dart`.

### Base de données SQLite (Vente & Don)

Fichier `campusconnect_vente_don.db` sur le téléphone (paquet `sqflite`), version 2 :

| Table | Contenu |
|---|---|
| `articles` | une colonne par champ (`title`, `price`, `category`, `status`, `latitude`, `created_at`, `view_count`…) ; photos, favoris et étiquettes IA en JSON |
| `conversations` | une ligne par article + acheteur : vendeur, acheteur, dernier message, non-lus |
| `messages` | `conversation_id`, `sender_id`, `text`, `sent_at` |

- Schéma et requêtes des articles : `lib/services/sqlite/article_database.dart`.
- Dépôt utilisé par le provider : `lib/services/sqlite/local_article_repository.dart`
  (interface `ArticleStore`).
- Messagerie : `lib/services/chat_service.dart`.
- Les données restent sur le téléphone : un autre téléphone ne voit pas les mêmes
  articles (choix du projet : SQLite à la place de Firebase).

### IA de la gestion Vente & Don

Code dans `lib/services/ai/`, tests dans `test/ai/`. Tout tourne **sur le téléphone**,
sauf la rédaction par Gemini qui passe par internet (sans Firebase).

**Activer Gemini** : crée une clé gratuite sur <https://aistudio.google.com/apikey> et mets-la
dans `.env.json` (copie de `.env.example.json`, **non versionné**) sous `GEMINI_API_KEY`, puis
lance `flutter run --dart-define-from-file=.env.json` (ou le bouton Run, configuré dans
`.vscode/launch.json`). Ne mets jamais la clé dans le code ni dans Git. Sans clé, le bouton
utilise la rédaction locale.

| Fonction | Où | Technique |
|---|---|---|
| Catégorie et mots-clés reconnus sur la photo | Formulaire « Publier » | Google ML Kit Image Labeling (modèle embarqué) |
| Prix conseillé (fourchette + bouton « Utiliser ») | Formulaire | Articles comparables : 1 titre proche, sinon 2 articles de la catégorie (quartiles), sinon prix habituel de la catégorie |
| Rédaction de la description | Formulaire, bouton « Rédiger avec l'IA » | **Par internet** : API Gemini (Google AI Studio, modèle `gemini-3.5-flash`, sans Firebase). Sans clé ou sans réseau : rédaction locale à partir du titre, de la catégorie, du prix et des mots-clés de la photo |
| Recommandations « Pour toi » | Liste Vente & Don | Profil favoris (×2) + articles consultés : catégorie, mots, étiquettes photo |
| Modération avant publication | Formulaire | Règles : objets interdits / insultes (bloquant), coordonnées, majuscules, prix suspect (avertissement) |
| Recherche par photo | Liste, bouton appareil photo | Étiquettes ML Kit de la photo comparées (Jaccard) à celles des articles |
| **Détection d'arnaques** (risque faible / moyen / élevé + raisons) | Page d'un article (acheteur) | **Modèle embarqué entraîné** : régression logistique (scikit-learn) sur 11 indices, poids dans `assets/models/fraud_model.json`, calcul dans le téléphone sans internet. Voir ci-dessous |
| **Assistant IA du chat** (répond à l'acheteur) | Conversation, dès que l'acheteur écrit | **Par internet** : LLM Gemini (même clé, `lib/services/ai/chat_replier.dart`) qui lit l'annonce et les derniers messages, avec des règles (pas de baisse de prix ni de réservation promise, remise sur le campus, jamais de paiement à l'avance). **Sans clé ou sans réseau** : modèle embarqué entraîné (12 intentions, français + darija), voir ci-dessous |

#### Modèle anti-arnaque

- Entraînement : `python tools/fraud_model/train_fraud_model.py` (Python 3, `pip install scikit-learn numpy`).
  Le script crée le jeu de données `tools/fraud_model/annonces.csv` (1 350 annonces : 900 normales,
  450 arnaques, avec 3 % d'étiquettes bruitées), entraîne le modèle sur 80 %, l'évalue sur les 20 %
  restants et écrit `assets/models/fraud_model.json`.
- Résultats sur les 270 annonces de test : exactitude 89 %, précision 94 %, rappel 73 %, F1 0,82
  (`metrics` dans le JSON).
- Indices : paiement à l'avance (virement, D17, Flouci, recharge…), contact hors de l'app
  (numéro, WhatsApp, lien), urgence, refus de rencontre sur le campus, objet de valeur trop bon
  marché, prix très bas, promesse « trop belle », don qui demande de payer, description courte,
  pas de photo, majuscules / « !!! ».
- Seuils : moyen dès 30 %, élevé dès 60 %. `test/ai/fraud_detector_test.dart` vérifie que l'app
  calcule exactement comme Python sur 40 annonces de test.

#### Assistant IA du chat (modèle embarqué de secours)

- Entraînement : `python tools/chat_model/train_chat_model.py`. Le script crée
  `tools/chat_model/questions.csv` (1 787 messages d'acheteurs générés à partir de formulations
  types, avec salutations, fautes de frappe et darija : « mazel? », « 9adech? », « win nitla9aw? »),
  entraîne sur 80 % et teste sur 20 % : exactitude 95 %.
- Intentions : salutation, disponibilité, prix, négociation, état, détails, lieu / heure de
  rendez-vous, livraison, photos, réservation, remerciement, autre (hors sujet).
- Réponses : construites avec l'annonce (« Oui, « Lampe » est toujours disponible. », « Le prix
  est de 25 DT. »…). Deux questions dans le même message → deux réponses. Hors sujet ou confiance
  < 45 % → « le vendeur te répondra directement ». L'assistant ne décide jamais à la place du
  vendeur (baisse de prix, réservation) et rappelle de ne jamais payer à l'avance.
- `test/ai/chat_assistant_test.dart` vérifie que l'app calcule exactement comme Python.

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

Polices **Outfit** (titres) et **Inter** (texte courant) via `google_fonts`.
Palette orange de marque (voir [décisions](docs/decisions.md)).

- **Tokens** : `lib/core/theme/app_colors.dart` (palette), `app_tokens.dart`
  (`ThemeExtension` avec les jeux `AppTokens.light` / `AppTokens.dark` : surfaces, textes,
  ombres, dégradés), `app_theme.dart` (thèmes Material clair et sombre), `contrast.dart`
  (vérification des contrastes en test).
- **Composants** (`lib/widgets/`) : `PrimaryButton`, `PillButton`, `RoundIconButton`,
  `SearchPill`, `FilterChipPill`, `StatusChip`, `StatusBadge`, `InitialsAvatar`,
  `SectionCard`, `SettingRow`, `StatTile`, `PhotoCard`, `FeaturedCard`, `EmptyState`,
  `SkeletonBox`, `HeroSheetScaffold` (héros + feuille), `BottomActionBar` et les
  graphiques `charts/` (`AreaLineChart`, `DonutChart`, `HBarChart`, basés sur `fl_chart`).
- **Barre flottante** : `FloatingNavBar` porte 5 onglets ; le profil s'ouvre par l'avatar
  de l'accueil. Chaque onglet réserve un espace bas pour ne pas être masqué par la barre.
- **Mode de thème** : `ThemeProvider` (`shared_preferences`) ; par défaut le thème suit le
  système, la ligne « Thème » du profil force Clair ou Sombre.
- **Galerie** : `lib/screens/debug/design_gallery_screen.dart` montre tous les composants
  en clair et en sombre. Elle n'est pas reliée à une route : on l'ouvre temporairement
  en la passant en `home` de l'app, ou via son test (`test/screens/design_gallery_screen_test.dart`).

### Concepts du cours mis en œuvre

| Concept | Où |
|---|---|
| `shared_preferences` | mode de thème, drapeau d'onboarding, préférence biométrique |
| `fl_chart` | accueil (activité de la semaine), anneau du profil, statistiques admin |
| `LayoutBuilder` | mise en page adaptative (accueil visiteur et connecté, héros d'authentification) |
| Hive (file d'attente) | `uploadStudentCard` : soumission de carte hors-ligne rejouée au retour du réseau |
| `path_provider` | copies locales des photos de carte en attente d'envoi |

## Captures d'écran

Thème clair et sombre dans `docs/screenshots/`. Les captures sont prises sur les émulateurs
Firebase avec les données de `tool/seed.sh` (comptes et cartes de démonstration, aucun
contenu des modules Vente & Don, Annonces, Événements ni Stages) :

| Écran | Clair | Sombre |
|---|---|---|
| Onboarding | [clair](docs/screenshots/onboarding_light.png) | [sombre](docs/screenshots/onboarding_dark.png) |
| Visiteur | [clair](docs/screenshots/visitor_light.png) | [sombre](docs/screenshots/visitor_dark.png) |
| Connexion | [clair](docs/screenshots/login_light.png) | [sombre](docs/screenshots/login_dark.png) |
| Inscription | [clair](docs/screenshots/register_light.png) | [sombre](docs/screenshots/register_dark.png) |
| Accueil | [clair](docs/screenshots/home_light.png) | [sombre](docs/screenshots/home_dark.png) |
| Profil | [clair](docs/screenshots/profile_light.png) | [sombre](docs/screenshots/profile_dark.png) |
| Édition du profil | [clair](docs/screenshots/edit_profile_light.png) | [sombre](docs/screenshots/edit_profile_dark.png) |
| Carte étudiante | [clair](docs/screenshots/student_card_light.png) | [sombre](docs/screenshots/student_card_dark.png) |
| Admin : utilisateurs | [clair](docs/screenshots/admin_users_light.png) | [sombre](docs/screenshots/admin_users_dark.png) |
| Admin : revue d'une carte | [clair](docs/screenshots/admin_card_review_light.png) | [sombre](docs/screenshots/admin_card_review_dark.png) |
| Admin : statistiques | [clair](docs/screenshots/admin_analytics_light.png) | [sombre](docs/screenshots/admin_analytics_dark.png) |

## 8. Builder pour la remise (APK de démonstration)

```bash
flutter build apk --release
# L'APK se trouve dans build/app/outputs/flutter-apk/app-release.apk
```

---

Projet réalisé dans le cadre du module **Développement Mobile** — ESPRIT.
