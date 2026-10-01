#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

[[ -x .runtime/venv/bin/python && -x .runtime/ollama/ollama ]] || {
  echo "Exécutez d'abord bash ci/Install-PhonePreview.sh"; exit 1;
}
export WEBTOON_LENS_RUNTIME="$PWD/.runtime"
export WEBTOON_LENS_CACHE="${WEBTOON_LENS_CACHE:-$PWD/.runtime/cache}"
export WEBTOON_LENS_OLLAMA_MODEL="${WEBTOON_LENS_OLLAMA_MODEL:-qwen3:4b-instruct-2507-q4_K_M}"
export OLLAMA_HOST=127.0.0.1:11434
export OLLAMA_MODELS="$PWD/.runtime/models"
export OLLAMA_NUM_PARALLEL=1
export OLLAMA_MAX_LOADED_MODELS=1
ollama_pid=""
cleanup() {
  if [[ -n "$ollama_pid" ]]; then kill "$ollama_pid" 2>/dev/null || true; fi
}
trap cleanup EXIT INT TERM

if ! curl -fsS --max-time 2 http://127.0.0.1:11434/api/version >/dev/null; then
  .runtime/ollama/ollama serve >.runtime/ollama.log 2>&1 &
  ollama_pid=$!
  ready=0
  for attempt in {1..30}; do
    if curl -fsS --max-time 1 http://127.0.0.1:11434/api/version >/dev/null 2>&1; then ready=1; break; fi
    sleep 1
  done
  [[ "$ready" == 1 ]] || { echo "Ollama ne démarre pas. Consultez .runtime/ollama.log"; exit 1; }
fi
if ! .runtime/ollama/ollama show "$WEBTOON_LENS_OLLAMA_MODEL" >/dev/null 2>&1; then
  .runtime/ollama/ollama pull "$WEBTOON_LENS_OLLAMA_MODEL"
fi
echo "Gardez ce terminal ouvert. Ctrl+C arrête le lecteur et l'Ollama démarré par ce script."
.runtime/venv/bin/python -u PhonePreview/server.py
