#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${APPLE_TEAM_ID:-}" ]]; then
  echo "Missing APPLE_TEAM_ID secret."
  exit 1
fi

if [[ -z "${WEBTOON_LENS_APP_PROFILE_NAME:-}" || -z "${WEBTOON_LENS_SAFARI_PROFILE_NAME:-}" ]]; then
  echo "Missing provisioning profile names. Did ci/install-profiles.sh run?"
  exit 1
fi

mkdir -p build/Archive build/Export

APP_BUNDLE_ID="${WEBTOON_LENS_V2_APP_BUNDLE_ID:-com.example.webtoonlens.v2}"
SAFARI_BUNDLE_ID="${WEBTOON_LENS_V2_SAFARI_BUNDLE_ID:-com.example.webtoonlens.v2.SafariExtension}"

cat > build/exportOptions.generated.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>teamID</key>
  <string>${APPLE_TEAM_ID}</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>${APP_BUNDLE_ID}</key>
    <string>${WEBTOON_LENS_APP_PROFILE_NAME}</string>
    <key>${SAFARI_BUNDLE_ID}</key>
    <string>${WEBTOON_LENS_SAFARI_PROFILE_NAME}</string>
  </dict>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>uploadSymbols</key>
  <true/>
</dict>
</plist>
EOF

xcodebuild archive \
  -scheme WebtoonLensV2 \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath build/Archive/WebtoonLensV2.xcarchive \
  DEVELOPMENT_TEAM="${APPLE_TEAM_ID}" \
  WEBTOON_LENS_APP_PROFILE_NAME="${WEBTOON_LENS_APP_PROFILE_NAME}" \
  WEBTOON_LENS_SAFARI_PROFILE_NAME="${WEBTOON_LENS_SAFARI_PROFILE_NAME}" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_ALLOWED=YES

xcodebuild -exportArchive \
  -archivePath build/Archive/WebtoonLensV2.xcarchive \
  -exportPath build/Export \
  -exportOptionsPlist build/exportOptions.generated.plist
