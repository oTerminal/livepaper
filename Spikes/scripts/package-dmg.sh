#!/bin/bash
# S0b: packages the built app for the second-Mac test.
#
#   package-dmg.sh [adhoc|selfsigned] [plain|hardened] [S0|S1]     default: selfsigned plain S1
#
# The default is the combination a release would use (self-signed, no hardened runtime,
# the read-only library exception). If that fails on the second Mac, build
# `adhoc plain S0` as well to tell a signing problem from an entitlement problem.
set -euo pipefail
IDENTITY=${1:-selfsigned} RUNTIME=${2:-plain} ENT=${3:-S1}
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$HERE/build/DerivedData/Build/Products/Release/Livepaper.app"
[ -d "$SOURCE" ] || { echo "run scripts/build.sh first"; exit 1; }
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$SOURCE" "$STAGE/Livepaper.app"
"$HERE/scripts/sign.sh" "$STAGE/Livepaper.app" "$IDENTITY" "$RUNTIME" "$ENT" | grep -E "verify|variant|designated"
ln -s /Applications "$STAGE/Applications"
VERSION=$(defaults read "$STAGE/Livepaper.app/Contents/Info.plist" CFBundleVersion)
OUT="$HERE/build/Livepaper-spike-$VERSION-$IDENTITY-$RUNTIME-$ENT.dmg"
hdiutil create -volname "Livepaper spike" -srcfolder "$STAGE" -ov -format UDZO "$OUT" >/dev/null
echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"
echo "spctl says (expected: rejected, this is what Open Anyway overrides):"
spctl --assess --type execute -vv "$STAGE/Livepaper.app" 2>&1 | sed 's/^/  /' || true
