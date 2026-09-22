#!/bin/zsh
# usage: shot.sh <out.png> [app name]
# Captures the app's main window (default: Livepaper Gallery) to a PNG, even when covered.
set -e
here=$(cd "$(dirname "$0")" && pwd)
out=$1; app=${2:-Livepaper Gallery}
[[ -x /tmp/pr-media-winid ]] || xcrun swiftc -O "$here/winid.swift" -o /tmp/pr-media-winid
read id x y w h <<< "$(/tmp/pr-media-winid "$app")"
[[ -n $id ]] || { echo "no window for $app" >&2; exit 1; }
screencapture -x -o -l "$id" "$out"
echo "$out ($w x $h pt)"
