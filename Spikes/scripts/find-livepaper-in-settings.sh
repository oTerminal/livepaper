#!/bin/bash
# S0's pass criterion, checked without eyes: is there a "Livepaper" entry in System Settings > Wallpaper?
# Reads the pane through the accessibility API, so the terminal needs the Accessibility permission.
# Prints the section headings of the pane and the tile that follows the "Livepaper" heading.
# With `click`, also clicks that tile (a real mouse click: the tile has no AXPress action).
set -euo pipefail
open "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension"
sleep 8   # a cold System Settings takes a while to build the pane
osascript <<'APPLESCRIPT' | tr ',' '\n' | sed 's/^ //'
tell application "System Events" to tell process "System Settings"
  set els to entire contents of window 1
  set out to {"window: " & (name of window 1), "accessibility elements: " & (count of els)}
  set found to false
  repeat with e in els
    try
      if (role of e) is "AXStaticText" then
        set end of out to "text: " & ((name of e) as text)
        if ((name of e) as text) is "Livepaper" then set found to true
      else if found and (role of e) is "AXButton" then
        set end of out to "tile after the Livepaper heading at " & ((item 1 of (position of e)) as text) & " x " & ((item 2 of (position of e)) as text)
        set found to false
      end if
    end try
  end repeat
  return out
end tell
APPLESCRIPT
