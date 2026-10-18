#!/usr/bin/env bash
# Lance CampusConnect en une commande.
#
#   tool/run.sh emu    → émulateurs Firebase locaux (aucun compte, aucun SMS réel)
#   tool/run.sh prod   → projet Firebase réel (Google Sign-In, vrais SMS)
#
# Pour `prod`, copie .env.example.json en .env.json et renseigne
# GOOGLE_WEB_CLIENT_ID (Firebase console → Authentication → Google → client Web).
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-emu}"
DEVICE_ARGS=()
if [[ -n "${2:-}" ]]; then DEVICE_ARGS=(-d "$2"); fi

case "$MODE" in
  emu)
    if ! curl -s -o /dev/null --max-time 2 http://127.0.0.1:9099/; then
      echo "▶ Démarrage des émulateurs Firebase (Auth 9099, Firestore 8085, Storage 9199)…"
      (firebase emulators:start --only auth,firestore,storage --project campusconnect-esprit \
        > /tmp/campusconnect-emulators.log 2>&1 &)
      for _ in $(seq 1 30); do
        curl -s -o /dev/null --max-time 1 http://127.0.0.1:9099/ && break
        sleep 1
      done
      echo "  UI des émulateurs : http://127.0.0.1:4000  (journal : /tmp/campusconnect-emulators.log)"
    fi
    echo "▶ flutter run (émulateurs). Les codes SMS et liens email s'affichent dans l'UI des émulateurs."
    exec flutter run "${DEVICE_ARGS[@]}" --dart-define=USE_EMULATOR=true
    ;;
  prod)
    if [[ -f .env.json ]]; then
      echo "▶ flutter run (projet réel) avec .env.json"
      exec flutter run "${DEVICE_ARGS[@]}" --dart-define-from-file=.env.json
    else
      echo "⚠ .env.json absent : Google Sign-In sera indisponible. Copie .env.example.json → .env.json."
      exec flutter run "${DEVICE_ARGS[@]}"
    fi
    ;;
  *)
    echo "usage : tool/run.sh [emu|prod] [deviceId]"; exit 1 ;;
esac
