# Note pour le responsable « Gestion des Utilisateurs » : faille dans `firestore.rules`

**De :** P4 (Événements) · **Fichier :** `firestore.rules`, bloc `match /users/{userId}`

## Le problème

```
allow create: if isOwner(userId);
allow update: if isOwner(userId) || isAdmin();
```

Un étudiant peut écrire **n'importe quel champ** de son propre document, y compris `role`.
Il lui suffit d'un appel Firestore (console du navigateur, app modifiée) :

```dart
FirebaseFirestore.instance.doc('users/<mon uid>').update({'role': 'admin'});
```

Ensuite, `isAdmin()` renvoie `true` pour lui partout : il peut supprimer les articles, annonces,
événements et offres de tout le monde, et lire toutes les candidatures.

## Correctif proposé (2 lignes changées)

```
match /users/{userId} {
  allow read: if true;
  // À l'inscription, on ne peut se donner que le rôle étudiant.
  allow create: if isOwner(userId) &&
    request.resource.data.get('role', 'student') == 'student';
  // Le propriétaire modifie son profil, mais pas son rôle ; seul un admin change un rôle.
  allow update: if isAdmin() ||
    (isOwner(userId) && !request.resource.data.diff(resource.data).affectedKeys().hasAny(['role']));
  allow delete: if isOwner(userId);
}
```

- Les comptes **recruteur** et **admin** sont alors attribués par un admin (ou à la main dans la console Firebase).
- Si l'app doit permettre de s'inscrire soi-même comme recruteur, remplacer `== 'student'` par
  `in ['student', 'recruiter']` (mais alors n'importe qui peut devenir recruteur).
- Vérifié dans le code : `AppUser.toMap()` écrit `role: 'student'` par défaut, donc l'inscription
  normale continue de fonctionner avec ce correctif.
- **Vie privée :** `allow read: if true` rend tous les profils lisibles par tout le monde, **e-mails compris** ;
  suggestion : limiter l'e-mail au propriétaire et aux admins (par exemple en le déplaçant dans un
  sous-document `users/{uid}/private/contact` lisible seulement par `isOwner(userId) || isAdmin()`).

## Test rapide (Rules Playground)

1. `update` sur `/users/<uid>` connecté en tant que `<uid>`, données `{ "fullName": "Nouveau nom" }` → **autorisé**.
2. Même chose avec `{ "role": "admin" }` → **refusé**.
