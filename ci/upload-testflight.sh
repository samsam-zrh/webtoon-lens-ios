#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${APP_STORE_CONNECT_KEY_ID:-}" || -z "${APP_STORE_CONNECT_ISSUER_ID:-}" || -z "${APP_STORE_CONNECT_API_KEY_BASE64:-}" ]]; then
  echo "Skipping App Store Connect upload."
  echo "To upload automatically, set APP_STORE_CONNECT_KEY_ID, APP_STORE_CONNECT_ISSUER_ID, and APP_STORE_CONNECT_API_KEY_BASE64."
  exit 0
fi

IPA_PATH="$(find build/Export -name '*.ipa' -print -quit)"
if [[ -z "${IPA_PATH}" ]]; then
  echo "No .ipa found in build/Export."
  exit 1
fi

KEY_DIR="${HOME}/.appstoreconnect/private_keys"
mkdir -p "${KEY_DIR}"
echo "${APP_STORE_CONNECT_API_KEY_BASE64}" | base64 --decode > "${KEY_DIR}/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"
chmod 600 "${KEY_DIR}/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"

xcrun altool \
  --upload-app \
  --type ios \
  --file "${IPA_PATH}" \
  --apiKey "${APP_STORE_CONNECT_KEY_ID}" \
  --apiIssuer "${APP_STORE_CONNECT_ISSUER_ID}"
