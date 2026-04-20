#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${BUILD_CERTIFICATE_BASE64:-}" || -z "${P12_PASSWORD:-}" || -z "${KEYCHAIN_PASSWORD:-}" ]]; then
  echo "Missing certificate secrets."
  echo "Required: IOS_DISTRIBUTION_CERTIFICATE_BASE64, IOS_DISTRIBUTION_CERTIFICATE_PASSWORD, IOS_BUILD_KEYCHAIN_PASSWORD"
  exit 1
fi

CERTIFICATE_PATH="${RUNNER_TEMP}/build_certificate.p12"
KEYCHAIN_PATH="${RUNNER_TEMP}/app-signing.keychain-db"

echo "${BUILD_CERTIFICATE_BASE64}" | base64 --decode > "${CERTIFICATE_PATH}"

security create-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"
security set-keychain-settings -lut 21600 "${KEYCHAIN_PATH}"
security unlock-keychain -p "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"
security import "${CERTIFICATE_PATH}" -P "${P12_PASSWORD}" -A -t cert -f pkcs12 -k "${KEYCHAIN_PATH}"
security list-keychain -d user -s "${KEYCHAIN_PATH}"
security set-key-partition-list -S apple-tool:,apple: -s -k "${KEYCHAIN_PASSWORD}" "${KEYCHAIN_PATH}"
