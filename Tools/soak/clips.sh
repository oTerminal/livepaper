#!/bin/bash
# usage: Tools/soak/clips.sh
# Makes the soak's two test clips (docs/specs/M8-hardening.md, The soak) in build/soak-clips/: a
# 1080p60 and a 4K60 HEVC clip, 10 s each, silent. testsrc2 draws a moving pattern and, in its top
# left corner, the time and the frame number, so a repeated or missing frame at the loop seam shows
# to the eye; that corner is also drawn enlarged at the bottom, to be read in a capture of the desktop.
# A clip already made is kept. The clips reach Livepaper through its importer: drag them into the
# library window. It needs an ffmpeg with lavfi and VideoToolbox, such as Homebrew's (FFMPEG=<path>
# picks another); the repo's Helpers/ffmpeg is built for the importer alone and has neither.
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
out=$root/build/soak-clips
ffmpeg=${FFMPEG:-$(command -v ffmpeg || true)}

fail() {
  echo "clips.sh: $*" >&2
  exit 1
}

[[ -n $ffmpeg && -x $ffmpeg ]] || fail "no ffmpeg on the PATH: brew install ffmpeg, or set FFMPEG=<path>"
# Read whole, not piped into grep -q: grep would stop reading at the match, and pipefail count
# ffmpeg's broken pipe as a failure.
filters=$("$ffmpeg" -hide_banner -filters 2>/dev/null || true)
encoders=$("$ffmpeg" -hide_banner -encoders 2>/dev/null || true)
[[ $filters == *' testsrc2 '* ]] || fail "$ffmpeg has no lavfi testsrc2"
[[ $encoders == *' hevc_videotoolbox '* ]] || fail "$ffmpeg has no hevc_videotoolbox"

clip() { # file size bitrate magnification
  local file=$out/$1 partial=$out/.$1.partial
  if [[ -f $file ]]; then
    echo "have $file"
    return
  fi
  # testsrc2's counter is a 100x36 box at (2, 2) whatever the frame's size. It is copied, scaled up
  # with its pixels kept square, and laid over the bottom centre; drawtext would need libfreetype,
  # which Homebrew's ffmpeg is built without.
  local enlarge="split[base][corner];[corner]crop=100:36:2:2,scale=iw*$4:ih*$4:flags=neighbor[big];"
  enlarge+="[base][big]overlay=(W-w)/2:H-h-H/12"
  # Written aside and moved into place, so an interrupted run leaves no half clip to be kept.
  "$ffmpeg" -hide_banner -loglevel error -y \
    -f lavfi -i "testsrc2=size=$2:rate=60:duration=10" -vf "$enlarge" \
    -c:v hevc_videotoolbox -b:v "$3" -tag:v hvc1 -pix_fmt yuv420p -an -f mov "$partial"
  mv "$partial" "$file"
  echo "made $file"
}

mkdir -p "$out"
clip soak-1080p60-hevc.mov 1920x1080 8M 6
clip soak-4k60-hevc.mov 3840x2160 40M 12
echo "Import them into Livepaper through its importer: drag both into the library window."
