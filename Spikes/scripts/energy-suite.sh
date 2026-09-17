#!/bin/bash
# S2's second half, and the 4K60 budget: CPU and energy impact of the sample-buffer
# engine against AVPlayerLooper in a window, then of the engine inside the extension.
# Run on battery-irrelevant mains power, machine otherwise idle. About 8 minutes.
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=build/Products/Livepaper.app/Contents/MacOS/Livepaper
APP=/Applications/Livepaper.app/Contents/MacOS/Livepaper
WARMUP=15 MEASURE=30

# System Settings on the Wallpaper pane holds a second (preview) surface, which would
# mean a second decode in the extension numbers.
osascript -e 'quit app "System Settings"' >/dev/null 2>&1
"$APP" config mode=colour >/dev/null 2>&1
sleep 20
echo "== baseline: extension showing the colour, nothing playing"
scripts/measure.sh $MEASURE WindowServer LivepaperExtension WallpaperAgent

for CLIP in a-1080p30-h264.mp4 a-4k60-hevc.mov; do
  for ENGINE in sbdl looper; do
    "$BIN" s2 engine=$ENGINE clip="$PWD/clips/$CLIP" loops=100000 >/dev/null 2>&1 &
    PID=$!
    sleep $WARMUP
    echo "== window, $ENGINE, $CLIP"
    scripts/measure.sh $MEASURE $PID WindowServer VTDecoderXPCService
    kill $PID 2>/dev/null; wait $PID 2>/dev/null
  done
done

for CLIP in a-1080p30-h264.mp4 a-4k60-hevc.mov; do
  "$APP" config mode=colour >/dev/null 2>&1
  "$APP" config mode=video video=$CLIP >/dev/null 2>&1
  sleep $WARMUP
  echo "== extension, desktop surface only, $CLIP"
  scripts/measure.sh $MEASURE LivepaperExtension WindowServer WallpaperAgent VTDecoderXPCService
done
"$APP" config mode=colour >/dev/null 2>&1
