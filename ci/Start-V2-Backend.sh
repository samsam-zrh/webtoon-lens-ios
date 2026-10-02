#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

port="${WEBTOON_LENS_V2_PORT:-8788}"
host="${WEBTOON_LENS_V2_HOST:-127.0.0.1}"
if [[ ! "$port" =~ ^[0-9]{4,5}$ ]] ||
   (( 10#$port < 1024 || 10#$port > 65535 || 10#$port == 8787 || 10#$port == 11434 )); then
  echo "Choisissez un port V2 libre entre 1024 et 65535, different de 8787 et 11434." >&2
  exit 1
fi
if [[ "$host" != 127.0.0.1 && "${WEBTOON_LENS_V2_ALLOW_LAN:-0}" != 1 ]]; then
  echo "Le reseau local exige WEBTOON_LENS_V2_ALLOW_LAN=1. Aucune exposition automatique." >&2
  exit 1
fi
if [[ ! -x .runtime/venv/bin/python ]]; then
  echo "Creez le venv Python dans CE checkout V2 et installez PhonePreview/requirements.txt. Consultez README.md." >&2
  exit 1
fi
export WEBTOON_LENS_RUNTIME="$PWD/.runtime/v2-backend"
export WEBTOON_LENS_CACHE="$PWD/.runtime/v2-backend/cache"
export WEBTOON_LENS_PREVIEW_PORT="$((10#$port))"
export WEBTOON_LENS_PREVIEW_HOST="$host"
export WEBTOON_LENS_OLLAMA_URL="http://127.0.0.1:11434"
export WEBTOON_LENS_OLLAMA_MODEL="qwen3:4b-instruct-2507-q4_K_M"
echo "Backend V2 : $host:$port ; runtime/cache propres a ce checkout."
echo "Ollama existant utilise uniquement par son API ; aucun lancement, arret ou telechargement de modele."
exec .runtime/venv/bin/python -u PhonePreview/server.py
