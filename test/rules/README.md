# Firestore rules tests

Tests of the `users` rules in `firestore.rules` (student card, `disabled`),
run against the Firestore emulator.

```
cd test/rules
npm install
npm test
```

`npm test` runs
`firebase emulators:exec --only firestore --project campusconnect-esprit "node --test firestore.rules.test.mjs"`
(needs the `firebase` CLI and Java; the Firestore emulator uses port 8085 from `firebase.json`).

Storage rules (`../../storage.rules`) are not unit-tested: the `student_cards`
read rule relies on a cross-service lookup (`firestore.get`) of the user's role,
which must be checked by hand with both emulators running:
`firebase emulators:start --only firestore,storage,auth`.
