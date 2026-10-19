# Module Événements (P4) — préparation de la soutenance

Les chemins sont relatifs à la racine du projet ; `E/` = `lib/screens/evenements/`.

## 1. Questions probables et réponses courtes

### Q1. Quelle différence entre un `StatelessWidget` et un `StatefulWidget` ? Un exemple dans ton module ?
Un `StatelessWidget` n'a pas d'état propre : il s'affiche à partir de ses paramètres (`EventHeroCard`, `E/event_hero_card.dart:16`). Un `StatefulWidget` garde un état qui change, et `setState()` redessine l'écran : le formulaire `AddEventScreen` (`E/add_event_screen.dart:24`, état à la ligne 35) garde les dates, l'affiche choisie, « envoi en cours »...
**À ouvrir** : `E/event_hero_card.dart:16`, `E/add_event_screen.dart:35`.

### Q2. Comment valides-tu le formulaire ?
Un `Form` avec une `GlobalKey<FormState>` (`E/add_event_screen.dart:609`) ; chaque `TextFormField` a un `validator` (ligne 632 : titre) qui renvoie un message d'erreur ou `null`. Les validateurs sont des fonctions pures dans `E/event_validators.dart`, donc testées sans écran (`test/evenements/event_validators_test.dart`). `_submit()` (ligne 459) appelle `validate()` avant tout envoi. `PopScope` (ligne 599) demande confirmation avant de quitter avec des modifications.
**À ouvrir** : `E/add_event_screen.dart:609`, `:632`, `:459`.

### Q3. Comment fonctionne Provider dans ton module ?
`EventProvider` (`lib/providers/event_provider.dart:49`) étend `ChangeNotifier` : il garde la liste, les filtres, le tri et appelle `notifyListeners()` quand ils changent. Il est déclaré dans `lib/main.dart:68` (`ChangeNotifierProxyProvider`, car il dépend de la connectivité). Les écrans font `context.watch<EventProvider>()` pour se redessiner (`E/evenements_list_screen.dart:165`) et `context.read` pour appeler une action sans se redessiner (`E/add_event_screen.dart:470`).
**Analogie** : le provider est un tableau d'affichage ; les écrans qui le *regardent* se mettent à jour quand on change une annonce.

### Q4. Comment navigues-tu entre les écrans ?
`Navigator.of(context).push(MaterialPageRoute(...))` : liste → calendrier (`E/evenements_list_screen.dart:144`), détail → participants (`E/event_detail_screen.dart:280`), détail → modification (`:321`). `Navigator.pop` pour revenir, avec une valeur de retour si besoin. La barre du bas de l'app est un `BottomNavigationBar` (`lib/screens/home/app_shell.dart:35`, fichier commun de l'équipe).

### Q5. Où utilises-tu `ListView.builder` / `GridView.builder` ? Pourquoi « builder » ?
Bande des jours : `ListView.builder` horizontal (`E/evenements_list_screen.dart:306`). Calendrier du mois : `GridView.builder` à 7 colonnes (`E/event_calendar_screen.dart:111`). « builder » ne construit que les éléments visibles à l'écran : c'est économe même avec beaucoup d'éléments.

### Q6. Comment l'écran de détail se met-il à jour tout seul ?
`StreamBuilder` (`E/event_detail_screen.dart:60`) écoute `watchEvent()` (`lib/providers/event_provider.dart:231`), qui renvoie le flux `snapshots()` de Firestore. Quand quelqu'un s'inscrit ailleurs, Firestore envoie le nouveau document et le `builder` redessine le compteur. Je n'utilise pas de `FutureBuilder` : pour les chargements uniques (météo, noms des participants), un `StatefulWidget` + `setState` (`_WeatherChip`, `E/event_detail_screen.dart:748`) me laisse gérer « hors-ligne », « annuler si on quitte l'écran » et « recharger si la date change ».
**Mots-clés** : Stream = plusieurs valeurs dans le temps ; Future = une seule valeur plus tard.

### Q7. Comment appelles-tu une API (http + JSON) ?
Exemple Photon (`E/photon_service.dart:95`) : `Uri.https(...)` construit l'URL (ligne 99), `await _client.get(...)` avec un délai maximum (ligne 109), puis `json.decode` (ligne 122) et lecture de `features`. Le résultat est une classe scellée `PhotonResponse` (succès / erreur) : l'écran fait un `switch` et n'a jamais d'exception à gérer. Le `http.Client` est injecté : dans les tests, un `MockClient` renvoie un faux JSON (`test/evenements/photon_service_test.dart`).

### Q8. À quoi servent `async` / `await` ?
Une fonction `async` renvoie un `Future` ; `await` attend le résultat sans bloquer l'interface. Exemple : `toggleRegistration` (`lib/providers/event_provider.dart:491`) attend la transaction Firestore (ligne 513), puis met à jour la liste. Après un `await`, je vérifie `mounted` avant d'utiliser le `context` (ex. `E/add_event_screen.dart:423`).

### Q9. Comment fonctionne le hors-ligne (Hive) ?
1. Chaque lecture réussie est copiée dans une boîte Hive (`load()`, `lib/providers/event_provider.dart:202`) ; sans réseau, la liste vient de ce cache.
2. Hive ne sait pas stocker un `Timestamp` Firestore : `toHiveSafe` (`lib/core/utils/local_cache_service.dart:6`) le convertit.
3. Une création hors-ligne part dans la file d'attente (`createEvent`, ligne 266 ; mise en file ligne 285) avec un id fixé d'avance : la renvoyer deux fois ne crée pas de doublon.
4. On met en file **seulement** pour « pas de réseau » / `unavailable` ; un `permission-denied` serait refusé à chaque essai, donc on affiche l'erreur (ligne 278).
5. L'inscription exige la connexion : la capacité doit être vérifiée par le serveur.

### Q10. Deux personnes prennent la dernière place en même temps : que se passe-t-il ?
L'inscription est une **transaction** (`lib/providers/event_provider.dart:513`) : on relit le document, on vérifie la place, on écrit. Si le document a changé entre-temps, Firestore rejoue la transaction ; la seconde personne voit « Complet ». Les règles (`firestore.rules:110`, `isOwnRegistrationDelta`) refusent aussi tout dépassement et toute modification d'un autre uid que le sien.

### Q11. Comment sécurises-tu les données (règles Firestore) ?
Bloc `events` de `firestore.rules` (ligne 71) : lecture publique ; création seulement pour soi-même (`organizerId == request.auth.uid`, ligne 205) avec un contenu valide (`validEvent`, ligne 83) ; modification par l'organisateur ou un admin sans toucher `organizerId` ; présences/paiements une personne à la fois (`isAttendanceChange`, ligne 174) ; suppression sans inscrits (ligne 215). Les contrôles d'heure utilisent `request.time` (heure du serveur) : changer l'heure du téléphone ne permet pas de tricher. Testés dans le Rules Playground.

### Q12. Comment as-tu organisé les onglets et les filtres de la liste ?
Un `TabBar` à 4 onglets *À venir / Passés / Mes inscriptions / Mes événements* (les deux derniers seulement si connecté) (`E/evenements_list_screen.dart:261`, `TabBar` ligne 264), relié à un `TabController`. Le filtrage est une fonction pure `EventRules` (testée) : onglet + jour + catégorie + prix + recherche sans accents. Le tri « Près de moi » (`enableNearMe`, `lib/providers/event_provider.dart:127`) lit la position une fois, la garde 5 minutes sans l'envoyer nulle part, et trie par distance haversine (`E/event_rules.dart:184`, tri ligne 203).

## 2. Démo en 5 minutes

Préparer avant : deux comptes connectés (A organisateur, B étudiant) sur deux appareils, position de l'émulateur sur Tunis, un événement existant avec affiche.

| Temps | Action | Ce qu'on dit |
|---|---|---|
| 0:00 | Onglet Événements : carte « Prochain événement », bande des jours, onglets | `TabBar`, `ListView.builder`, Provider |
| 0:30 | 🔍 « ecole » → trouve « École » ; ⚙ catégorie Sport ; Trier par → Près de moi | règles pures testées, haversine, position non partagée |
| 1:15 | 📅 calendrier du mois → toucher un jour | `GridView.builder`, Navigator |
| 1:45 | A : **+** → titre vide → erreurs ; lieu « ariana » → suggestion ; affiche ; capacité 2 ; prix 10 → Créer | `Form` + `validator`, Photon (http + JSON), Cloudinary |
| 2:45 | B ouvre l'événement → S'inscrire ; sur A le compteur passe à 1 sans rien toucher | `StreamBuilder`, transaction |
| 3:15 | Détail : météo, carte, Itinéraire, Ajouter au calendrier | Open-Meteo, OSRM, add_2_calendar |
| 3:45 | B : Mon billet → QR ; A : Participants → Scanner → « Présent » | qr_flutter, mobile_scanner, règles de pointage |
| 4:20 | Mode avion sur A : liste toujours là, bandeau ; créer un événement → le bandeau compte 1 action en attente ; réseau revenu → envoyé | Hive, file d'attente, id fixé d'avance |
| 4:45 | ⋮ → Supprimer avec un inscrit → refusé, « Annuler l'événement » proposé | règles métier + règles Firestore |

## 3. Ce que j'améliorerais

- **Cloud Functions** :
  - supprimer l'affiche Cloudinary quand l'événement est supprimé ou l'affiche remplacée (impossible avec un envoi *unsigned*) ;
  - **billets signés** (HMAC côté serveur) pour qu'un QR copié ou fabriqué soit rejeté ;
  - **notifications push** (rappel la veille, annulation, place libérée).
- **Règles côté serveur pour l'heure** : `createdAt` / `updatedAt` en `request.time` (aujourd'hui heure du téléphone, à cause de la file Hive), refuser la modification d'un événement terminé.
- **Mode sombre** avec les couleurs de catégorie adaptées.
- **Tests avec l'émulateur Firebase** (`@firebase/rules-unit-testing`) pour prouver automatiquement les règles, la transaction et le temps réel.
- Liste paginée (`limit` + `startAfter`) si le nombre d'événements devient grand.
