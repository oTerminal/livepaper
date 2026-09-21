#!/bin/bash
# Generates the throwaway test clips used by the spike rows. Not committed.
# testsrc2 burns in a frame counter and a moving pattern, so a repeated or
# missing frame at the loop seam is visible to the eye.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p clips

gen() { # name size fps codec extra...
  local name=$1 size=$2 fps=$3 codec=$4; shift 4
  [ -f "clips/$name" ] && { echo "have clips/$name"; return; }
  ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "testsrc2=size=$size:rate=$fps:duration=5" \
    -c:v "$codec" "$@" -pix_fmt yuv420p -an "clips/$name"
  echo "made clips/$name"
}

# A and B differ in hue so a switch or crossfade is obvious.
gen a-1080p30-h264.mp4  1920x1080 30 h264_videotoolbox -b:v 8M
gen a-1080p60-hevc.mov  1920x1080 60 hevc_videotoolbox -b:v 8M -tag:v hvc1
gen a-4k60-hevc.mov     3840x2160 60 hevc_videotoolbox -b:v 40M -tag:v hvc1

[ -f clips/b-1080p30-h264.mp4 ] || ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc2=size=1920x1080:rate=30:duration=5" -vf "hue=h=120" \
  -c:v h264_videotoolbox -b:v 8M -pix_fmt yuv420p -an clips/b-1080p30-h264.mp4
[ -f clips/b-4k60-hevc.mov ] || ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc2=size=3840x2160:rate=60:duration=5" -vf "hue=h=120" \
  -c:v hevc_videotoolbox -b:v 40M -tag:v hvc1 -pix_fmt yuv420p -an clips/b-4k60-hevc.mov

# The loop-seam flash reported in Wallper: an audio track longer than the video track. The engine reads
# the video track only, so this must loop exactly like the silent clip.
[ -f clips/a-1080p30-long-audio.mp4 ] || ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc2=size=1920x1080:rate=30:duration=5" \
  -f lavfi -i "sine=frequency=440:duration=5.4" \
  -c:v h264_videotoolbox -b:v 8M -pix_fmt yuv420p -c:a aac clips/a-1080p30-long-audio.mp4

# B-frames and the edit list ffmpeg writes for them: first PTS is not zero in
# media time. libx264 is only used here as a local clip generator.
[ -f clips/a-1080p30-bframes.mp4 ] || ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc2=size=1920x1080:rate=30:duration=5" \
  -c:v libx264 -bf 2 -g 60 -pix_fmt yuv420p -an clips/a-1080p30-bframes.mp4

ls -la clips
