#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "Ce script cible les Mac Apple Silicon. Consultez PhonePreview/README.md pour le moteur portable."
  exit 1
fi
command -v xcrun >/dev/null || { echo "Installez les outils Apple : xcode-select --install"; exit 1; }
python3 -c 'import sys; assert sys.version_info >= (3, 9), "Python 3.9 ou plus est requis."'
python3 -m venv .runtime/venv
.runtime/venv/bin/python -m pip install -r PhonePreview/requirements.txt
mkdir -p .runtime/ollama
if [[ ! -x .runtime/ollama/ollama ]]; then
  curl -fL --retry 2 -o .runtime/ollama-darwin.tgz \
    https://github.com/ollama/ollama/releases/download/v0.35.0/ollama-darwin.tgz
  printf '2608dbb0a0f0136a198db9d48b4f74ece55f452314a39452fca35b7cf20c2589  .runtime/ollama-darwin.tgz\n' | shasum -a 256 -c -
  tar -xzf .runtime/ollama-darwin.tgz -C .runtime/ollama
fi
echo "Installation prête. Lancez bash ci/Start-PhonePreview.sh ; le premier démarrage télécharge le modèle (2,5 Go)."
