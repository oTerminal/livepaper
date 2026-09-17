#!/bin/bash
# Removes everything the spike put on this Mac. The wallpaper choice itself is changed
# back by hand in System Settings > Wallpaper.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
KEYCHAIN="$HOME/Library/Keychains/livepaper-spike.keychain-db"
pkill -x Livepaper
for APP in /Applications/Livepaper.app "$HERE/build/DerivedData/Build/Products/Release/Livepaper.app" "$HERE/build/Products/Livepaper.app"; do
  [ -d "$APP" ] && "$LSREGISTER" -u "$APP"
done
rm -rf /Applications/Livepaper.app "$HERE/build"
rm -rf "$HOME/Library/Application Support/LivepaperSpike"
rm -rf "$HOME/Library/Containers/app.livepaper.spike.extension"
if [ -f "$KEYCHAIN" ]; then
  # shellcheck disable=SC2046
  security list-keychains -d user -s $(security list-keychains -d user | sed -e 's/^ *"//' -e 's/"$//' | grep -vF "$KEYCHAIN")
  security delete-keychain "$KEYCHAIN"
fi
killall WallpaperAgent
echo "done. pluginkit now lists:"; pluginkit -m -p com.apple.wallpaper | grep -ci livepaper
