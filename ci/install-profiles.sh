#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${APP_PROFILE_BASE64:-}" || -z "${SAFARI_PROFILE_BASE64:-}" ]]; then
  echo "Missing provisioning profile secrets."
  echo "Required: IOS_APP_PROFILE_BASE64, IOS_SAFARI_EXTENSION_PROFILE_BASE64"
  exit 1
fi

PROFILE_DIR="${HOME}/Library/MobileDevice/Provisioning Profiles"
mkdir -p "${PROFILE_DIR}"

APP_PROFILE_PATH="${PROFILE_DIR}/webtoon-lens-app.mobileprovision"
SAFARI_PROFILE_PATH="${PROFILE_DIR}/webtoon-lens-safari.mobileprovision"

echo "${APP_PROFILE_BASE64}" | base64 --decode > "${APP_PROFILE_PATH}"
echo "${SAFARI_PROFILE_BASE64}" | base64 --decode > "${SAFARI_PROFILE_PATH}"

security cms -D -i "${APP_PROFILE_PATH}" > /tmp/webtoon-lens-app-profile.plist
security cms -D -i "${SAFARI_PROFILE_PATH}" > /tmp/webtoon-lens-safari-profile.plist

echo "Installed app profile:"
APP_PROFILE_NAME="$(/usr/libexec/PlistBuddy -c "Print :Name" /tmp/webtoon-lens-app-profile.plist)"
echo "${APP_PROFILE_NAME}"

echo "Installed Safari extension profile:"
SAFARI_PROFILE_NAME="$(/usr/libexec/PlistBuddy -c "Print :Name" /tmp/webtoon-lens-safari-profile.plist)"
echo "${SAFARI_PROFILE_NAME}"

{
  echo "WEBTOON_LENS_APP_PROFILE_NAME=${APP_PROFILE_NAME}"
  echo "WEBTOON_LENS_SAFARI_PROFILE_NAME=${SAFARI_PROFILE_NAME}"
} >> "${GITHUB_ENV}"
