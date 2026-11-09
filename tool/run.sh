#!/usr/bin/env bash
# Lance CampusConnect en une commande.
#
#   tool/run.sh [deviceId]
#
# Pas de serveur : toutes les données sont dans SQLite sur le téléphone. Au
# premier lancement (base vide), l'app crée les comptes de démonstration
# (mot de passe Campus2026!) et leurs contenus, voir lib/services/demo_seed.dart.
# Pour repartir de zéro, désinstalle l'app ou efface ses données.
# Si .env.json existe (ex. GEMINI_API_KEY), ses valeurs sont passées à l'app.
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE_ARGS=()
if [[ -n "${1:-}" ]]; then DEVICE_ARGS=(-d "$1"); fi

if [[ -f .env.json ]]; then
  exec flutter run "${DEVICE_ARGS[@]}" --dart-define-from-file=.env.json
fi
exec flutter run "${DEVICE_ARGS[@]}"
