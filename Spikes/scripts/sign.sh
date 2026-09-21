#!/bin/bash
# Signs a built Livepaper.app inside-out: the extension first, with its entitlements
# file, then the app. Never --deep. No hardened runtime unless asked.
#
#   sign.sh <app> [adhoc|selfsigned] [plain|hardened] [S0|S1]
#
# S0 entitlements = app-sandbox only. S1 adds the read-only home-relative exception
# for ~/Library/Application Support/LivepaperSpike/.
set -euo pipefail
APP=${1:?app path}
IDENTITY_KIND=${2:-adhoc}
RUNTIME=${3:-plain}
ENT=${4:-S0}
HERE="$(cd "$(dirname "$0")/.." && pwd)"
APPEX="$APP/Contents/Extensions/LivepaperExtension.appex"

case "$IDENTITY_KIND" in
  adhoc) IDENTITY="-" ;;
  selfsigned) # "spike" is make-cert.sh's throwaway keychain password, not a secret
    IDENTITY="Livepaper Spike Self-Signed"
    security unlock-keychain -p spike "$HOME/Library/Keychains/livepaper-spike.keychain-db" ;;
  *) echo "unknown identity kind $IDENTITY_KIND"; exit 2 ;;
esac
FLAGS=(--force --timestamp=none --sign "$IDENTITY")
[ "$RUNTIME" = hardened ] && FLAGS+=(--options runtime)

codesign "${FLAGS[@]}" --entitlements "$HERE/Extension/Extension-$ENT.entitlements" "$APPEX"
codesign "${FLAGS[@]}" "$APP"
codesign --verify --strict --verbose=2 "$APP" 2>&1 | sed 's/^/  verify: /'

echo "  variant: $IDENTITY_KIND / $RUNTIME / entitlements $ENT"
for BUNDLE in "$APP" "$APPEX"; do
  echo "  $(basename "$BUNDLE"):"
  codesign -d --verbose=2 "$BUNDLE" 2>&1 | grep -E "^(Identifier|CodeDirectory|Signature|Authority|TeamIdentifier|Runtime)" | sed 's/^/    /'
  codesign -d -r- "$BUNDLE" 2>&1 | grep "designated" || true | sed 's/^/    /'
done
echo "  extension entitlements:"
codesign -d --entitlements - --xml "$APPEX" 2>/dev/null | plutil -p - | sed 's/^/    /'
