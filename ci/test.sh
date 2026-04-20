#!/usr/bin/env bash
set -euo pipefail

mkdir -p build/TestResults

SIMULATOR_NAME="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ && /Shutdown|Booted/ { name=$1; gsub(/^[ \t]+|[ \t]+$/, "", name); print name; exit }')"

if [[ -z "${SIMULATOR_NAME}" ]]; then
  echo "No available iPhone simulator found."
  xcrun simctl list devices available
  exit 1
fi

echo "Using simulator: ${SIMULATOR_NAME}"

xcodebuild test \
  -scheme WebtoonLens \
  -destination "platform=iOS Simulator,name=${SIMULATOR_NAME},OS=latest" \
  -resultBundlePath build/TestResults/WebtoonLens.xcresult \
  CODE_SIGNING_ALLOWED=NO
