#!/bin/bash
# Runs one S0 variant end to end and appends what was observed to results/S0-variants.md.
# Assumes "Livepaper" was chosen once in System Settings > Wallpaper, so a restarted
# WallpaperAgent acquires from whichever copy of the extension is now registered.
#
#   s0-variant.sh deriveddata|applications adhoc|selfsigned plain|hardened [S0|S1]
set -euo pipefail
WHERE=$1 IDENTITY=$2 RUNTIME=$3 ENT=${4:-S0} LABEL=${5:-}
HERE="$(cd "$(dirname "$0")/.." && pwd)"
NAME="s0-$IDENTITY-$WHERE-$RUNTIME-$ENT"
RAW="$HERE/results/raw/$NAME.log"
mkdir -p "$HERE/results/raw"

"$HERE/scripts/logs.sh" > "$RAW" 2>&1 &
STREAM=$!
sleep 1
"$HERE/scripts/install.sh" "$WHERE" "$IDENTITY" "$RUNTIME" "$ENT" > "$HERE/results/raw/$NAME.install.txt" 2>&1
killall WallpaperAgent
sleep 14
kill $STREAM 2>/dev/null || true

spike() { grep -F "[app.livepaper.spike:spike]" "$RAW" | sed -E 's/^([0-9-]+ [0-9:.]+).*\[app.livepaper.spike:spike\] /\1 /' ; }
{
  echo "### $IDENTITY / $WHERE / $RUNTIME / entitlements $ENT $LABEL"
  echo
  echo "Run $(date '+%Y-%m-%d %H:%M:%S'), macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion))."
  echo
  echo '```'
  grep -E "variant:|Signature=|Authority=|flags=|designated|pluginkit|spike.extension\(" "$HERE/results/raw/$NAME.install.txt" | sed 's/^ *//' | cut -c1-200
  echo "--- extension"
  spike | grep -E "INIT|bridge:|ACQUIRE|SNAPSHOT|PROVIDE" | cut -c1-230 | head -8
  echo "--- amfid / kernel / ExtensionKit"
  grep -E "amfid\[|AMFI:|not entitled|deny\(" "$RAW" | grep -v "vfs.disk-space" | sed -E 's#/Users/[^ ]*/Livepaper.app#<app>#g' | cut -c1-250 | sort -u -k4 | head -8
  echo '```'
  if spike | grep -q "ACQUIRE"; then echo "Result: extension launched and was acquired by WallpaperAgent."; else echo "Result: NO acquire seen."; fi
  echo
} >> "$HERE/results/S0-variants.md"
tail -22 "$HERE/results/S0-variants.md"
