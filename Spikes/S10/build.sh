#!/bin/bash
# build.sh spike|normal : builds the Livepaper app from the scratch export, into its own DerivedData.
set -uo pipefail
S=/private/tmp/claude-501/-Users-vaibhavprakash-Programming-livepaper/75d00fd0-b01c-4036-b5e7-832dec946c51/scratchpad/s10
KIND=${1:?spike|normal}
cd "$S/$KIND-src" || exit 1
xcodegen generate --quiet
EXTRA=()
if [ "$KIND" = spike ]; then EXTRA=('SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) LIVEPAPER_S10'); fi
/usr/bin/xcodebuild -project Livepaper.xcodeproj -scheme Livepaper -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$S/dd-$KIND" build ${EXTRA[@]+"${EXTRA[@]}"} > "$S/build-$KIND.log" 2>&1
STATUS=$?
echo "xcodebuild exit $STATUS"
grep -E ' error: |BUILD (SUCCEEDED|FAILED)|\*\* ' "$S/build-$KIND.log" | grep -v deprecated | head -40
/bin/ls -la "$S/dd-$KIND/Build/Products/Debug/" | grep -i livepaper
exit $STATUS
