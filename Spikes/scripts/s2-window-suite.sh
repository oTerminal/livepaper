#!/bin/bash
# S2 in a plain window: the 200-loop pass criterion, then shorter runs on the awkward
# clips. Keep the machine quiet and do not cover the window while this runs.
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=build/Products/Livepaper.app/Contents/MacOS/Livepaper
mkdir -p results/raw
run() { # label clip loops
  "$BIN" s2 engine=sbdl clip="$PWD/clips/$2" loops="$3" probe=2 out="results/raw/s2-window-$1.json" >/dev/null 2>&1
  echo "== $1 ($3 loops)"; scripts/missing-frames.py < "results/raw/s2-window-$1.json"
}
run 1080p30-h264-200 a-1080p30-h264.mp4 200
run 1080p30-bframes a-1080p30-bframes.mp4 20
run 1080p30-long-audio a-1080p30-long-audio.mp4 20
run 1080p60-hevc a-1080p60-hevc.mov 20
run 4k60-hevc a-4k60-hevc.mov 20
