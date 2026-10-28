#!/usr/bin/env bash
# Crée des comptes de démonstration dans les émulateurs Firebase (Auth + Firestore)
# et dépose une photo de carte (Storage) pour les cartes en attente.
# Idempotent : un compte existant est réutilisé, son document users/{uid} et sa
# photo de carte sont réécrits. Toute réponse HTTP hors 2xx arrête le script.
# Prérequis : émulateurs lancés (tool/run.sh emu).
set -euo pipefail

AUTH="http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1"
FS="http://127.0.0.1:8085/v1/projects/campusconnect-esprit/databases/(default)/documents"
# Bucket des apps Android/iOS (lib/firebase_options.dart), pas celui du web.
ST="http://127.0.0.1:9199/v0/b/campusconnect-esprit.firebasestorage.app/o"
CARD_JPEG="$(cd "$(dirname "$0")/.." && pwd)/assets/images/cover_campus.jpg"
PASSWORD='Campus2026!'
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

curl -s -o /dev/null --max-time 2 http://127.0.0.1:9099/ || { echo "Émulateurs Firebase injoignables (tool/run.sh emu)"; exit 1; }

# http label curl-args... : imprime le corps de la réponse, échoue (exit 1)
# avec un message clair si le code HTTP n'est pas 2xx. Les erreurs attendues
# (EMAIL_EXISTS) sont traitées par l'appelant via http_try.
HTTP_BODY="$(mktemp)"
trap 'rm -f "$HTTP_BODY"' EXIT
http_try() { # imprime "code" ; le corps est dans $HTTP_BODY
  curl -s -o "$HTTP_BODY" -w '%{http_code}' --max-time 15 "$@" || echo 000
}
http() {
  local label="$1" code; shift
  code="$(http_try "$@")"
  if [[ "$code" != 2* ]]; then
    echo "Échec HTTP $code : $label" >&2
    sed 's/^/  /' "$HTTP_BODY" | head -5 >&2
    exit 1
  fi
  cat "$HTTP_BODY"
}

uid_of() { sed -n 's/.*"localId": *"\([^"]*\)".*/\1/p' | head -1; }

# create_account email -> imprime l'uid
create_account() {
  local email="$1" body resp
  body="{\"email\":\"$email\",\"password\":\"$PASSWORD\",\"returnSecureToken\":true}"
  local code
  code="$(http_try -X POST "$AUTH/accounts:signUp?key=any" -H 'Content-Type: application/json' -d "$body")"
  if [[ "$code" == 2* ]]; then
    resp="$(cat "$HTTP_BODY")"
  elif grep -q EMAIL_EXISTS "$HTTP_BODY"; then
    resp="$(http "connexion $email" -X POST "$AUTH/accounts:signInWithPassword?key=any" \
      -H 'Content-Type: application/json' -d "$body")"
  else
    echo "Échec HTTP $code : création du compte $email" >&2
    sed 's/^/  /' "$HTTP_BODY" | head -5 >&2
    exit 1
  fi
  echo "$resp" | uid_of
}

# write_user uid email fullName role verified cardJson skillsJson
write_user() {
  local uid="$1" email="$2" name="$3" role="$4" verified="$5" card="$6" skills="$7"
  http "profil users/$uid" -X PATCH "$FS/users/$uid" \
    -H 'Authorization: Bearer owner' -H 'Content-Type: application/json' -d "{
    \"fields\": {
      \"fullName\": {\"stringValue\": \"$name\"},
      \"email\": {\"stringValue\": \"$email\"},
      \"role\": {\"stringValue\": \"$role\"},
      \"isVerifiedStudent\": {\"booleanValue\": $verified},
      \"isPhoneVerified\": {\"booleanValue\": false},
      \"ratingAverage\": {\"integerValue\": \"0\"},
      \"ratingCount\": {\"integerValue\": \"0\"},
      \"skills\": {\"arrayValue\": {\"values\": $skills}},
      \"campus\": {\"stringValue\": \"ESPRIT Ghazela\"},
      \"disabled\": {\"booleanValue\": false},
      \"createdAt\": {\"timestampValue\": \"$NOW\"},
      \"studentCard\": {\"mapValue\": {\"fields\": $card}}
    }}" > /dev/null
}

# upload_card uid : photo de carte factice à student_cards/{uid}/seed.jpg
# (le chemin référencé par pending_card), pour que « Voir la carte » l'affiche.
upload_card() {
  local uid="$1"
  http "photo de carte student_cards/$uid/seed.jpg" -X POST \
    "$ST?uploadType=media&name=student_cards%2F$uid%2Fseed.jpg" \
    -H 'Authorization: Bearer owner' -H 'Content-Type: image/jpeg' \
    --data-binary "@$CARD_JPEG" > /dev/null
}

pending_card() {
  echo "{\"status\":{\"stringValue\":\"pending\"},\"imagePath\":{\"stringValue\":\"student_cards/$1/seed.jpg\"},\"submittedAt\":{\"timestampValue\":\"$NOW\"}}"
}
NONE='{"status":{"stringValue":"none"}}'
SKILLS='[{"stringValue":"Flutter"},{"stringValue":"Firebase"}]'
NOSKILLS='[]'

declare -a OUT
LAST_UID=""
add() { # email name role verified cardkind skills
  local email="$1" name="$2" role="$3" verified="$4" kind="$5" skills="$6" uid card
  uid="$(create_account "$email")"
  LAST_UID="$uid"
  [[ -n "$uid" ]] || { echo "Échec pour $email"; exit 1; }
  if [[ "$kind" == pending ]]; then
    upload_card "$uid"
    card="$(pending_card "$uid")"
  else
    card="$NONE"
  fi
  write_user "$uid" "$email" "$name" "$role" "$verified" "$card" "$skills"
  OUT+=("$(printf '%-24s %-10s carte: %-8s uid=%s' "$email" "$role" "$kind" "$uid")")
}

add admin@esprit.tn      "Admin Campus"   admin     true  none    "$NOSKILLS"; ADMIN_UID="$LAST_UID"
add amel@esprit.tn       "Amel Ben Salah" student   false pending "$SKILLS"; AMEL_UID="$LAST_UID"
add sarra@esprit.tn      "Sarra Trabelsi" student   false pending "$SKILLS"; SARRA_UID="$LAST_UID"
add youssef@esprit.tn    "Youssef Gharbi" student   false pending "$SKILLS"; YOUSSEF_UID="$LAST_UID"
add recruteur@vermeg.tn  "Recruteur Vermeg" recruiter false none  "$NOSKILLS"; RECRUITER_UID="$LAST_UID"
# Carte déposée ici, validée ensuite par seed_demo.py (profil de la maquette).
add jawher@esprit.tn     "Jawher Khalifa" student   false pending "$SKILLS"; JAWHER_UID="$LAST_UID"

echo "Comptes de démonstration (mot de passe : $PASSWORD)"
printf '%s\n' "${OUT[@]}"

# Contenu de la maquette : annonces, articles, événements, offres, candidatures
# et comptes fictifs pour l'écran Analytics. SEED_DEMO=0 pour s'en passer.
if [[ "${SEED_DEMO:-1}" != 0 ]]; then
  ADMIN_UID="$ADMIN_UID" AMEL_UID="$AMEL_UID" SARRA_UID="$SARRA_UID" YOUSSEF_UID="$YOUSSEF_UID" \
  RECRUITER_UID="$RECRUITER_UID" JAWHER_UID="$JAWHER_UID" \
    python3 "$(dirname "$0")/seed_demo.py"
fi
