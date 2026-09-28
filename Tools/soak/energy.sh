#!/bin/bash
# usage: energy.sh video <wallpaper> [--watts]   the 4K60 clip: paused, playing, covered, display asleep
#        energy.sh scene <wallpaper> [--watts]   the same four phases with a scene
#        energy.sh idle                          the app, then the extension covered, 5 minutes each
#
# S2's energy suite on product code (docs/specs/M8-hardening.md, Energy, idle and memory). <wallpaper>
# is a name or UUID in the library, as `livepaper set` takes it. One display, mains, the machine
# otherwise idle; System Settings is quit, and caffeinate -dis keeps the Mac and its display awake
# while this runs. Each run's folder is ~/Library/Logs/Livepaper energy/<YYYY-MM-DD-HHMM>/:
#   energy.csv  phase,second,process,pid,cpu,power,mem_kb: a row per process per top sample, for
#               WallpaperExtension, its VTDecoderXPCService, WindowServer and Livepaper; `power`
#               is top's energy impact score and `mem_kb` its memory footprint, which shows the
#               decoder's session going (the service itself never exits, M5-engine.md); `second`
#               is counted from the phase's start, or for
#               covered and displayAsleep from the moment TextEdit is fullscreen or the display sleeps
#   watts.csv   phase,second,combined_mw,gpu_mw, with --watts: powermetrics "must be invoked as the
#               superuser", so sudo asks once
# and the end prints Tools/soak/soak-report's reading. LIVEPAPER=<path> picks the livepaper tool, by
# default the running Livepaper's own. The covered phase drives TextEdit through System Events, which
# needs Accessibility for the terminal. Run it as yourself, not with sudo.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
runs="$HOME/Library/Logs/Livepaper energy"
dir=""
tool=""
watts=0
known=""
top_pid=""
watts_pid=""
textedit_ran=0
document=""

say() { printf '%s  %s\n' "$(date +%H:%M:%S)" "$*"; }

fail() {
  echo "energy.sh: $*" >&2
  exit 1
}

usage() {
  sed -n '2,4s/^# \{0,1\}//p' "$0" >&2
  exit 2
}

ask() { # prompt
  printf '%s  %s ' "$(date +%H:%M:%S)" "$1"
  read -r _
}

# MARK: Livepaper

# The livepaper tool: LIVEPAPER, else the one inside the running Livepaper, else the PATH's, else
# /Applications'. It ships inside the app, at Contents/Helpers/livepaper (M7-system-integration.md).
find_tool() {
  local app candidate
  if [[ -n ${LIVEPAPER:-} ]]; then
    [[ -x $LIVEPAPER ]] || fail "LIVEPAPER is not an executable: $LIVEPAPER"
    echo "$LIVEPAPER"
    return 0
  fi
  app=$(ps -axo comm= | awk '/\/Livepaper\.app\/Contents\/MacOS\/Livepaper$/ && !found { print; found = 1 }')
  for candidate in "${app:+${app%/MacOS/Livepaper}/Helpers/livepaper}" "$(command -v livepaper || true)" \
    /Applications/Livepaper.app/Contents/Helpers/livepaper; do
    if [[ -n $candidate && -x $candidate ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

lp() {
  "$tool" "$@" > /dev/null || fail "livepaper $* did not work"
}

# MARK: Conditions

on_mains() { [[ $(pmset -g batt) == *"'AC Power'"* ]]; }

display_count() {
  system_profiler SPDisplaysDataType -json 2>/dev/null | grep -c '"_spdisplays_resolution"' || true
}

# System Settings on the Wallpaper pane holds a second surface, a preview, which would add a second
# decode to the numbers.
close_settings() {
  pgrep -x "System Settings" > /dev/null || return 0
  osascript -e 'quit app "System Settings"' > /dev/null || say "warning: System Settings would not quit"
  sleep 2
}

# MARK: Sampling

# "pid name" pairs, on one line, for the processes measured. The app and its extension are known by
# their paths, so another app's WallpaperExtension is not counted. VideoToolbox runs a
# VTDecoderXPCService for each client, in the client's launchd domain, which `launchctl print
# pid/<pid>` lists without root: only the extension's are the wallpaper's, where the other clients'
# copies would stay in every sample and hide the decoder leaving.
known_processes() {
  local pairs extension service
  pairs=$(ps -axo pid=,comm= | awk '
    { pid = $1; sub(/^ *[0-9]+ /, "") }
    /\/Livepaper\.app\/Contents\/MacOS\/Livepaper$/ { printf "%s Livepaper ", pid }
    /\/Livepaper\.app\/Contents\/Extensions\/WallpaperExtension\.appex\/Contents\/MacOS\/WallpaperExtension$/ {
      printf "%s WallpaperExtension ", pid
    }
    /\/WindowServer$/ { printf "%s WindowServer ", pid }')
  while read -r extension; do
    while read -r service; do
      if [[ $(ps -o comm= -p "$service" 2>/dev/null || true) == */VTDecoderXPCService ]]; then
        pairs+="$service VTDecoderXPCService "
      fi
    done < <(launchctl print "pid/$extension" 2>/dev/null |
      awk '/^\tservices = \{/ { on = 1; next } on && /^\t\}/ { on = 0 } on && $1 ~ /^[0-9]+$/ { print $1 }')
  done < <(awk '{ for (i = 1; i < NF; i += 2) if ($(i + 1) == "WallpaperExtension") print $i }' <<< "$pairs")
  echo "$pairs"
}

# Starts `count` top samples `every` seconds apart in the background, and one more before them,
# which is dropped: the first has no interval behind it, so its CPU means nothing.
start_top() { # count every
  known=$(known_processes)
  LC_ALL=C top -l $(($1 + 1)) -s "$2" -stats pid,cpu,power,mem > "$dir/top.txt" 2>/dev/null &
  top_pid=$!
}

# Waits for top and appends its samples from `first` to `last` seconds after t0 to energy.csv, each
# timed by the clock line top prints with it. The processes are read again once top is done, so a
# decoder the extension started during the phase is counted too.
finish_top() { # phase t0 first last
  wait "$top_pid" || say "top failed during $1"
  known+=" $(known_processes)"
  awk -v phase="$1" -v t0="$(date -r "$2" +%H:%M:%S)" -v first="$3" -v last="$4" -v known="$known" '
    function clock(hms, part) { split(hms, part, ":"); return part[1] * 3600 + part[2] * 60 + part[3] }
    # top prints memory as 512B, 3425K, 31M or 1.2G, with a + or - when it moved since the last sample.
    function kilobytes(text, unit, value) {
      sub(/[+-]$/, "", text)
      unit = substr(text, length(text)); value = substr(text, 1, length(text) - 1) + 0
      if (unit == "B") return int(value / 1024)
      if (unit == "K") return int(value)
      if (unit == "M") return int(value * 1024)
      if (unit == "G") return int(value * 1024 * 1024)
      return int(text)
    }
    BEGIN {
      n = split(known, pair, " ")
      for (i = 1; i < n; i += 2) name[pair[i]] = pair[i + 1]
      start = clock(t0)
    }
    /^Processes:/ { sample++; next }
    /^[0-9][0-9][0-9][0-9]\/[0-9][0-9]\/[0-9][0-9] / {
      second = clock($2) - start
      if (second < -43200) second += 86400 # past midnight
      next
    }
    sample >= 2 && NF == 4 && ($1 in name) && second >= first && second <= last {
      printf "%s,%d,%s,%s,%s,%s,%d\n", phase, second, name[$1], $1, $2, $3, kilobytes($4)
    }' "$dir/top.txt" >> "$dir/energy.csv"
  rm -f "$dir/top.txt"
}

# powermetrics beside top, one sample a second, when --watts asked for it.
start_watts() { # count
  ((watts)) || return 0
  sudo -n -v 2> /dev/null || say "warning: sudo has timed out, so this phase has no watts"
  # The output is the person's file, written by this shell; only powermetrics runs as root.
  # shellcheck disable=SC2024
  sudo -n powermetrics --samplers cpu_power,gpu_power -i 1000 -n "$1" > "$dir/powermetrics.txt" 2>/dev/null &
  watts_pid=$!
}

# Appends powermetrics' samples to watts.csv as finish_top does top's. Each sample opens with
# "*** Sampled system activity (<date>) …" and holds "Combined Power (CPU + GPU + ANE): <n> mW" and
# "GPU Power: <n> mW", which both samplers may print; the first is taken.
finish_watts() { # phase t0 first last
  ((watts)) || return 0
  wait "$watts_pid" || say "powermetrics failed during $1"
  awk -v phase="$1" -v t0="$(date -r "$2" +%H:%M:%S)" -v first="$3" -v last="$4" '
    function clock(hms, part) { split(hms, part, ":"); return part[1] * 3600 + part[2] * 60 + part[3] }
    function flush() {
      if (combined != "" && second >= first && second <= last) printf "%s,%d,%s,%s\n", phase, second, combined, gpu
      combined = gpu = ""
    }
    BEGIN { start = clock(t0) }
    /^\*\*\* Sampled system activity/ {
      flush()
      if (match($0, /[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/)) {
        second = clock(substr($0, RSTART, RLENGTH)) - start
        if (second < -43200) second += 86400
      }
      next
    }
    /^Combined Power/ && combined == "" { combined = $(NF - 1) }
    /^GPU Power:/ && gpu == "" { gpu = $(NF - 1) }
    END { flush() }' "$dir/powermetrics.txt" >> "$dir/watts.csv"
  rm -f "$dir/powermetrics.txt"
}

# A steady phase: its action at second 0, 15 s to settle, then six 5 s samples.
steady() { # phase livepaper-command
  local t0
  say "$1: livepaper $2, 15 s to settle, then six 5 s samples"
  lp "$2"
  t0=$(date +%s)
  sleep 15
  start_top 6 5
  start_watts 30
  finish_top "$1" "$t0" 0 999
  finish_watts "$1" "$t0" 0 999
}

# MARK: Covering

# A new TextEdit document, made fullscreen and back through System Events. TextEdit is launched
# without its open panel, and quit afterwards only if it was not running before, so the person's
# own documents are left alone.
open_document() {
  textedit_ran=0
  if pgrep -x TextEdit > /dev/null; then textedit_ran=1; fi
  document=$(osascript -e 'tell application "TextEdit"' -e 'launch' -e 'set d to make new document' \
    -e 'activate' -e 'return name of d' -e 'end tell') || fail "TextEdit would not make a document"
  sleep 3
}

fullscreen() { # true|false
  osascript -e "tell application \"System Events\" to tell process \"TextEdit\" to set value of attribute \"AXFullScreen\" of front window to $1" \
    > /dev/null || fail "System Events could not change fullscreen: Privacy & Security, Accessibility, allow this terminal"
}

close_document() {
  osascript -e "tell application \"TextEdit\" to close document \"$document\" saving no" > /dev/null || true
  if ((!textedit_ran)); then osascript -e 'tell application "TextEdit" to quit saving no' > /dev/null || true; fi
}

# The desktop covered: second 0 is the moment TextEdit is fullscreen, and 1 s samples run to second 10.
# top starts 2 s before, so that its dropped first sample is behind it.
covered() {
  local t0
  say "covered: TextEdit fullscreen over the desktop, 1 s samples for 10 s"
  open_document
  start_top 14 1
  start_watts 14
  sleep 2
  fullscreen true
  t0=$(date +%s)
  finish_top covered "$t0" 0 10
  finish_watts covered "$t0" 0 10
  fullscreen false
  sleep 2
  close_document
}

# The display asleep: second 0 is pmset displaysleepnow, then 1 s samples to second 10, then
# `caffeinate -u` wakes it as a key would.
display_asleep() {
  local t0
  say "displayAsleep: pmset displaysleepnow, 1 s samples for 10 s"
  start_top 14 1
  start_watts 14
  sleep 2
  pmset displaysleepnow > /dev/null
  t0=$(date +%s)
  finish_top displayAsleep "$t0" 0 10
  finish_watts displayAsleep "$t0" 0 10
  caffeinate -u -t 5
  say "the display is awake: unlock if the lock screen shows"
}

# MARK: Runs

wallpaper_run() { # wallpaper
  local displays
  displays=$(display_count)
  [[ $displays == 1 ]] || fail "S2's budget is for one display, and $displays are connected"
  tool=$(find_tool) || fail "no livepaper tool: open Livepaper, or set LIVEPAPER=<…/Livepaper.app/Contents/Helpers/livepaper>"
  if ((watts)); then
    say "powermetrics must be invoked as the superuser: sudo asks once"
    sudo -v || fail "no sudo, so no watts: run it without --watts"
  fi
  ask "About 3 minutes: keep the desktop visible and leave the Mac alone. Return starts."
  lp set "$1"
  lp resume
  say "showing $1: 15 s to settle"
  sleep 15
  steady paused pause
  steady playing resume
  covered
  say "playing again: 15 s to settle"
  sleep 15
  display_asleep
}

idle_run() {
  local t0
  ask "idleApp: close Livepaper's popover and every Livepaper window, then press return; 5 minutes, hands off."
  t0=$(date +%s)
  start_top 60 5
  finish_top idleApp "$t0" 0 999
  ask "idleExtension: a wallpaper playing on every display, a fullscreen app over each, then return; 5 minutes."
  t0=$(date +%s)
  start_top 60 5
  finish_top idleExtension "$t0" 0 999
}

# A scene's numbers are a baseline, held to no budget (M8-hardening.md), so the report is told.
report() {
  local args=(energy --samples "$dir/energy.csv")
  if ((watts)); then args+=(--watts "$dir/watts.csv"); fi
  if [[ $mode == scene ]]; then args+=(--scene); fi
  say "the run: $dir"
  if [[ -x $here/soak-report ]]; then
    "$here/soak-report" "${args[@]}" | tee "$dir/report.md"
  else
    say "Tools/soak/soak-report is missing: run it on $dir/energy.csv once it is built"
  fi
}

mode=${1:-}
wallpaper=""
[[ $# -eq 0 ]] || shift
case $mode in
  video | scene)
    [[ $# -ge 1 ]] || usage
    wallpaper=$1
    shift
    while (($#)); do
      case $1 in
        --watts) watts=1 ;;
        *) usage ;;
      esac
      shift
    done
    ;;
  idle) [[ $# -eq 0 ]] || usage ;;
  *) usage ;;
esac
# Run as root, the tool would look for the app's socket in root's home and open a second Livepaper
# there, and System Events would act for no one; powermetrics alone needs root.
((EUID != 0)) || fail "run it as yourself; --watts asks for sudo for powermetrics"
on_mains || say "warning: on battery, where a pause rule may suspend playback; S2's budget is on mains"

dir=$runs/$(date +%Y-%m-%d-%H%M)
[[ ! -e $dir/energy.csv ]] || fail "$dir holds a run already: try again in a minute"
mkdir -p "$dir"
echo 'phase,second,process,pid,cpu,power,mem_kb' > "$dir/energy.csv"
if ((watts)); then echo 'phase,second,combined_mw,gpu_mw' > "$dir/watts.csv"; fi
caffeinate -dis -w $$ &
close_settings
case $mode in
  video | scene) wallpaper_run "$wallpaper" ;;
  idle) idle_run ;;
esac
report
