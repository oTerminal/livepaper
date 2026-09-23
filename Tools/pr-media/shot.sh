#!/bin/zsh
# usage: shot.sh <out.png> [app name or pid [layer] | --desktop [n]]
# Captures the app's main window (default: Livepaper Gallery) to a PNG, even when covered.
# The layer picks a window above the normal level (default 0): 101 is Livepaper's menu-bar
# popover, `shot.sh popover.png Livepaper 101`. The popover's panel is transparent around the
# glass, and a window capture has none of the desktop behind the glass.
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
