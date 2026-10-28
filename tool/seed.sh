#!/usr/bin/env bash
# Crée des comptes de démonstration dans les émulateurs Firebase (Auth + Firestore).
# Idempotent : un compte existant est réutilisé, son document users/{uid} est réécrit.
# Prérequis : émulateurs lancés (tool/run.sh emu).
set -euo pipefail

AUTH="http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1"
FS="http://127.0.0.1:8085/v1/projects/campusconnect-esprit/databases/(default)/documents"
PASSWORD='Campus2026!'
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

curl -s -o /dev/null --max-time 2 http://127.0.0.1:9099/ || { echo "Émulateurs Firebase injoignables (tool/run.sh emu)"; exit 1; }

uid_of() { sed -n 's/.*"localId": *"\([^"]*\)".*/\1/p' | head -1; }

# create_account email -> imprime l'uid
create_account() {
  local email="$1" body resp
  body="{\"email\":\"$email\",\"password\":\"$PASSWORD\",\"returnSecureToken\":true}"
  resp="$(curl -s -X POST "$AUTH/accounts:signUp?key=any" -H 'Content-Type: application/json' -d "$body")"
  if echo "$resp" | grep -q EMAIL_EXISTS; then
    resp="$(curl -s -X POST "$AUTH/accounts:signInWithPassword?key=any" -H 'Content-Type: application/json' -d "$body")"
  fi
  echo "$resp" | uid_of
}

# write_user uid email fullName role verified cardJson skillsJson
write_user() {
  local uid="$1" email="$2" name="$3" role="$4" verified="$5" card="$6" skills="$7"
  curl -s -o /dev/null -X PATCH "$FS/users/$uid" \
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
    }}"
}

pending_card() {
  echo "{\"status\":{\"stringValue\":\"pending\"},\"imagePath\":{\"stringValue\":\"student_cards/$1/seed.jpg\"},\"submittedAt\":{\"timestampValue\":\"$NOW\"}}"
}
NONE='{"status":{"stringValue":"none"}}'
SKILLS='[{"stringValue":"Flutter"},{"stringValue":"Firebase"}]'
NOSKILLS='[]'

declare -a OUT
add() { # email name role verified cardkind skills
  local email="$1" name="$2" role="$3" verified="$4" kind="$5" skills="$6" uid card
  uid="$(create_account "$email")"
  [[ -n "$uid" ]] || { echo "Échec pour $email"; exit 1; }
  if [[ "$kind" == pending ]]; then card="$(pending_card "$uid")"; else card="$NONE"; fi
  write_user "$uid" "$email" "$name" "$role" "$verified" "$card" "$skills"
  OUT+=("$(printf '%-24s %-10s carte: %-8s uid=%s' "$email" "$role" "$kind" "$uid")")
}

add admin@esprit.tn      "Admin Campus"   admin     true  none    "$NOSKILLS"
add amel@esprit.tn       "Amel Ben Salah" student   false pending "$SKILLS"
add sarra@esprit.tn      "Sarra Trabelsi" student   false pending "$SKILLS"
add youssef@esprit.tn    "Youssef Gharbi" student   false pending "$SKILLS"
add recruteur@vermeg.tn  "Recruteur Vermeg" recruiter false none  "$NOSKILLS"

echo "Comptes de démonstration (mot de passe : $PASSWORD)"
printf '%s\n' "${OUT[@]}"
