#!/bin/zsh
# usage: fakes.sh <command words…>
# Drives Livepaper's fakes run (`Livepaper -fakes YES`) from a script, for the manual
# script and the PR's media when the menu-bar item cannot be clicked. Commands:
#   open popover | close popover | open library | open settings | quit
#   menu <title>    chooses the Fakes menu item with that title, e.g. menu Recovering at Restart Agent
# The command is heard by every fakes run on this Mac and by nothing else.
set -e
here=$(cd "$(dirname "$0")" && pwd)
[[ /tmp/pr-media-fakes -nt "$here/fakes.swift" ]] || xcrun swiftc -O "$here/fakes.swift" -o /tmp/pr-media-fakes
/tmp/pr-media-fakes "$@"
