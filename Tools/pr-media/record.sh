#!/bin/zsh
# usage: record.sh <name> <seconds> [crop x y w h] [app name]
# Records the app's main window (default: Livepaper Gallery) for <seconds> and writes <name>.mp4 and
# <name>.gif beside each other. The crop is in window pixels (2x on a Retina display) and should
# frame the control that moves: a whole-window GIF is unreadable in a PR.
set -e
here=$(cd "$(dirname "$0")" && pwd)
name=$1; secs=$2; shift 2
crop=""
if [[ $# -ge 4 && $1 == <-> ]]; then crop="crop=$3:$4:$1:$2,"; shift 4; fi
app=${1:-Livepaper Gallery}
[[ -x /tmp/pr-media-winid ]] || xcrun swiftc -O "$here/winid.swift" -o /tmp/pr-media-winid
read id x y w h <<< "$(/tmp/pr-media-winid "$app")"
[[ -n $id ]] || { echo "no window for $app" >&2; exit 1; }
screencapture -x -v -R "$x,$y,$w,$h" -V "$secs" "$name.mov" 2>/dev/null
ffmpeg -v error -y -i "$name.mov" -vf "${crop}scale='min(960,iw)':-2" \
  -c:v libx264 -preset slow -crf 26 -pix_fmt yuv420p -movflags +faststart -an "$name.mp4"
ffmpeg -v error -y -i "$name.mov" \
  -vf "${crop}fps=12,scale='min(600,iw)':-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128[p];[b][p]paletteuse=dither=bayer:bayer_scale=3" \
  "$name.gif"
rm -f "$name.mov"
echo "$name.mp4 $name.gif"
