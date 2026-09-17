#!/bin/bash
# Puts one signed copy of the spike app in place and registers it, removing any other
# copy first so pkd cannot pick a stale one.
#
#   install.sh deriveddata|applications [adhoc|selfsigned] [plain|hardened] [S0|S1]
set -euo pipefail
WHERE=${1:?deriveddata|applications}
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$HERE/build/DerivedData/Build/Products/Release/Livepaper.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[ -d "$SOURCE" ] || { echo "run scripts/build.sh first"; exit 1; }

pkill -x Livepaper 2>/dev/null || true
case "$WHERE" in
  deriveddata)
    if [ -d /Applications/Livepaper.app ]; then "$LSREGISTER" -u /Applications/Livepaper.app || true; rm -rf /Applications/Livepaper.app; fi
    APP="$SOURCE" ;;
  applications)
    "$LSREGISTER" -u "$SOURCE" 2>/dev/null || true
    rm -rf /Applications/Livepaper.app
    cp -R "$SOURCE" /Applications/Livepaper.app
    APP=/Applications/Livepaper.app ;;
  *) echo "deriveddata|applications"; exit 2 ;;
esac

"$HERE/scripts/sign.sh" "$APP" "${2:-adhoc}" "${3:-plain}" "${4:-S0}"
"$LSREGISTER" -f -R "$APP"
open "$APP"
sleep 4
# After a (re)registration, the first extension instance gets removed by pkd at a following
# launch of the host app, once, and WallpaperAgent does not start it again (results/S0.md,
# "Hazard"). A launch in the same second as the extension's start finds nothing, so keep
# launching until the instance is gone (or 30 s pass), then restart the agent: what follows
# is stable.
wait_for_extension() { for _ in $(seq 1 40); do pgrep -x LivepaperExtension >/dev/null && return 0; sleep 0.25; done; return 1; }
killall WallpaperAgent 2>/dev/null || true
if wait_for_extension; then
  for _ in $(seq 1 10); do
    sleep 3
    "$APP/Contents/MacOS/Livepaper" login status >/dev/null 2>&1 || true
    sleep 1
    pgrep -x LivepaperExtension >/dev/null || break
  done
  killall WallpaperAgent 2>/dev/null || true
  wait_for_extension || true
fi
echo "  pluginkit:"
pluginkit -m -v -p com.apple.wallpaper | grep -i livepaper | sed 's/^/    /' || echo "    NOT LISTED"
