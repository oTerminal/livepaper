#!/bin/zsh
# usage: shot.sh <out.png> [app name | --desktop [n]]
# Captures the app's main window (default: Livepaper Gallery) to a PNG, even when covered.
# --desktop captures the desktop's wallpaper window on the nth display from the left (default 1),
# which is what the wallpaper extension draws into; it needs Screen Recording for the terminal.
set -e
here=$(cd "$(dirname "$0")" && pwd)
out=$1; shift
target=("$@"); (( $# )) || target=("Livepaper Gallery")
[[ /tmp/pr-media-winid -nt "$here/winid.swift" ]] || xcrun swiftc -O "$here/winid.swift" -o /tmp/pr-media-winid
read id x y w h <<< "$(/tmp/pr-media-winid "${target[@]}")"
[[ -n $id ]] || { echo "no window for ${target[*]}" >&2; exit 1; }
screencapture -x -o -l "$id" "$out"
echo "$out ($w x $h pt)"
