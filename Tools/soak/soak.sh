#!/bin/bash
# usage: soak.sh start [--dir DIR]                    begins a soak, or carries on one not stopped
#        soak.sh mark <kind> [note]                   a person's row, just before the act:
#                                                     lid, replug, fus, drill, lock or note
#        soak.sh night [--from HH:MM] [--to HH:MM]    sleeps every 20 minutes (sudo once, for the wakes)
#        soak.sh displaysleep [count]                 display sleep, woken 30 s later (default 10)
#        soak.sh lock [count] | lock --person         the lock screen (default 8; the person's 2)
#        soak.sh stop                                 ends the soak, writes docs/reports/soak-<date>.md
#        soak.sh status
#
# Drives M8's 24-hour soak (docs/specs/M8-hardening.md, The soak) and keeps its record in a run
# folder, ~/Library/Logs/Livepaper soak/<YYYY-MM-DD-HHMM>/ unless --dir names another:
#   events.csv   time,kind,note; start, sleep, displaysleep, lock, lid, replug, fus, drill, note, end
#   samples.csv  time,process,pid,cpu,rss_kb; Livepaper, WallpaperExtension and WallpaperAgent,
#                every 5 minutes
#   log.txt      `log show --info` of both Livepaper subsystems in the default style, exported every
#                hour so that the system's log rotation cannot lose any of it
# `start` runs in the foreground for the whole soak: leave it in a terminal, or run it as
# `nohup Tools/soak/soak.sh start > ~/soak.out 2>&1 &`. It waits for the host's next live, which a
# Livepaper live already gives when it is quit and opened again. The other commands run in another
# terminal and add to the same run, whose folder is kept in ~/Library/Logs/Livepaper soak/current.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
runs="$HOME/Library/Logs/Livepaper soak"
current="$runs/current"
metrics=app.livepaper.playback-metrics
predicate='subsystem == "app.livepaper.extension" OR subsystem == "app.livepaper.Livepaper"'
sample_every=${SOAK_SAMPLE_EVERY:-60}
export_every=${SOAK_EXPORT_EVERY:-1800}
run=""

say() { printf '%s  %s\n' "$(date +%H:%M:%S)" "$*"; }

fail() {
  echo "soak.sh: $*" >&2
  exit 1
}

usage() {
  sed -n '2,9s/^# \{0,1\}//p' "$0" >&2
  exit 2
}

# MARK: Time

iso_now() { date +%Y-%m-%dT%H:%M:%S%z; }
epoch_of() { date -j -f %Y-%m-%dT%H:%M:%S%z "$1" +%s; }
clock() { date -r "$1" +%H:%M:%S; }
# log show's --start and --end: local time, to the second.
log_time() { date -r "$1" '+%Y-%m-%d %H:%M:%S'; }
duration() { printf '%dh %02dm' $(($1 / 3600)) $(($1 % 3600 / 60)); }

# Waits on the wall clock, which moves on while the Mac sleeps; sleep(1)'s time does not.
wait_until() {
  while (($(date +%s) < $1)); do sleep 5; done
}

# The next time the clock reads HH:MM, at or after the epoch given.
next_at() { # HH:MM epoch
  local day t
  [[ $1 =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]] || fail "not a time: $1 (HH:MM)"
  day=$(date -r "$2" +%Y-%m-%d)
  t=$(date -j -f '%Y-%m-%d %H:%M:%S' "$day $1:00" +%s)
  ((t >= $2)) || t=$(date -j -v+1d -f '%Y-%m-%d %H:%M:%S' "$day $1:00" +%s)
  echo "$t"
}

# MARK: The run

# The current run's folder; `open_run` also wants it not ended.
find_run() {
  [[ -f $current ]] || fail "no soak: soak.sh start begins one"
  run=$(<"$current")
  [[ -f $run/events.csv ]] || fail "the current soak's folder is gone: $run"
}

open_run() {
  find_run
  ! has_event end || fail "the soak in $run has ended: soak.sh start begins another"
}

has_event() { awk -F, -v kind="$1" 'NR > 1 && $2 == kind { found = 1 } END { exit !found }' "$run/events.csv"; }
count_events() { awk -F, -v kind="$1" 'NR > 1 && $2 == kind { n++ } END { print n + 0 }' "$run/events.csv"; }
first_time() { awk -F, -v kind="$1" 'NR > 1 && $2 == kind && !done { print $1; done = 1 }' "$run/events.csv"; }
sample_count() { awk -F, 'NR > 1 && $1 != last { n++; last = $1 } END { print n + 0 }' "$run/samples.csv"; }

event() { # kind [note]
  local note=${2:-}
  note=${note//,/;} # the note is the last column, but a comma would still split the row
  printf '%s,%s,%s\n' "$(iso_now)" "$1" "$note" >> "$run/events.csv"
}

# The pid of the run's `start`, while it runs.
sampler_pid() {
  local pid
  [[ -f $run/sampler.pid ]] || return 1
  pid=$(<"$run/sampler.pid")
  [[ $(ps -o command= -p "$pid" 2>/dev/null || true) == *soak.sh* ]] || return 1
  echo "$pid"
}

# Marks this shell as the run's `start`, until it ends: ctrl-C in its terminal or `soak.sh stop`.
# It also holds caffeinate -i, so the Mac never idle-sleeps: a system sleep during the soak is then
# either the night's script or a person's lid. caffeinate goes when this shell does.
claim_run() {
  echo $$ > "$run/sampler.pid"
  trap 'rm -f "$run/sampler.pid"; say "stopped: soak.sh stop ends the soak, soak.sh start carries on"; exit 0' INT TERM
  caffeinate -i -w $$ &
}

# MARK: Livepaper

# The soak wants one stable install; a second registered copy of the extension is the install
# hazard (S0.md), not something the soak should find.
check_extension_copies() {
  local listed copies
  listed=$(pluginkit -m -v -i app.livepaper.Livepaper.WallpaperExtension 2>/dev/null |
    grep 'app.livepaper.Livepaper.WallpaperExtension(' || true)
  copies=$(grep -c . <<< "$listed" || true)
  if ((copies == 0)); then
    say "warning: pluginkit lists no Livepaper wallpaper extension"
  elif ((copies > 1)); then
    say "warning: pluginkit lists $copies copies of the extension; the soak wants one stable install:"
    echo "$listed"
  fi
}

# The host's first `host: status live` since the epoch given, in the compact style.
live_line() { # since
  /usr/bin/log show --style compact --start "$(log_time "$1")" \
    --predicate 'subsystem == "app.livepaper.Livepaper" AND category == "host" AND eventMessage == "host: status live"' \
    2>/dev/null | awk '/host: status live/ && !found { print; found = 1 }'
}

# The clock starts at the host's first live (M8-hardening.md), and the report reads it from log.txt,
# which runs from `start`: a Livepaper live already is quit and opened again, and the start row is
# written when its live is logged.
wait_for_live() { # since
  local line
  if pgrep -x Livepaper > /dev/null; then
    say "Livepaper is running: if it is live already, quit it and open it again; the soak starts at its next live"
  else
    say "Livepaper is not running: open it; the soak starts at its first live"
  fi
  until line=$(live_line "$1") && [[ -n $line ]]; do sleep 5; done
  say "live: $line"
  event start
}

# Keeps Log Playback Metrics on the way the app's menu item does (ExtensionHostClient's
# setPlaybackMetrics): the notification's state set to 1, then posted. The app does not keep the
# switch across launches and posts it off at each activation, so it is looked at with every sample.
# A state set with no one registered for it is lost, so while the extension is down this does nothing.
keep_metrics_on() {
  [[ $(notifyutil -g "$metrics" | awk '{ print $NF }') != 1 ]] || return 0
  notifyutil -s "$metrics" 1 -p "$metrics" > /dev/null
  say "playback metrics were off: switched on"
}

# MARK: Samples and the log

# The processes sampled, as "pid name" lines. The app and its extension are known by their paths,
# so another app's WallpaperExtension is not counted; ps gives the whole path, where top cuts a
# command at 16 characters (WallpaperExtensi) and pgrep at 15.
soak_processes() {
  ps -axo pid=,comm= | awk '
    { pid = $1; sub(/^ *[0-9]+ /, "") }
    /\/Livepaper\.app\/Contents\/MacOS\/Livepaper$/ { print pid, "Livepaper" }
    /\/Livepaper\.app\/Contents\/Extensions\/WallpaperExtension\.appex\/Contents\/MacOS\/WallpaperExtension$/ {
      print pid, "WallpaperExtension"
    }
    /\/WallpaperAgent\.app\/Contents\/MacOS\/WallpaperAgent$/ { print pid, "WallpaperAgent" }'
}

# One row per running process. The CPU is top's second sample, taken over the second after the first:
# an instantaneous figure, where ps's %cpu decays over the process's life; the first has no interval
# behind it. A process gone between the reads gets no row.
sample() {
  local processes time cpu rss pid name c r line="" args=()
  processes=$(soak_processes)
  if [[ -z $processes ]]; then
    say "sample: none of Livepaper, its extension or WallpaperAgent is running"
    return
  fi
  time=$(iso_now)
  while read -r pid name; do args+=(-pid "$pid"); done <<< "$processes"
  cpu=$(LC_ALL=C top -l 2 -s 1 -stats pid,cpu "${args[@]}" 2>/dev/null |
    awk '/^PID/ { n++; next } n == 2 && $1 ~ /^[0-9]+$/ { print $1, $2 }' || true)
  rss=$(ps -o pid=,rss= -p "$(cut -d' ' -f1 <<< "$processes" | paste -sd, -)" 2>/dev/null || true)
  while read -r pid name; do
    c=$(awk -v pid="$pid" '$1 == pid { print $2 }' <<< "$cpu")
    r=$(awk -v pid="$pid" '$1 == pid { print $2 }' <<< "$rss")
    [[ -n $c && -n $r ]] || continue
    printf '%s,%s,%s,%s,%s\n' "$time" "$name" "$pid" "$c" "$r" >> "$run/samples.csv"
    line+="  $name ${c}% $((r / 1024)) MB"
  done <<< "$processes"
  say "sample $(sample_count):$line"
}

# Appends the log since the last export. log show's --end is exclusive to the second, so one export
# ends where the next begins with no line twice and none missed. It is written aside first, so a
# failed export leaves log.txt as it was and the next one covers its time.
export_log() {
  local from to
  from=$(<"$run/exported")
  to=$(date +%s)
  if /usr/bin/log show --info --start "$(log_time "$from")" --end "$(log_time "$to")" \
    --predicate "$predicate" > "$run/log.part" 2>/dev/null; then
    cat "$run/log.part" >> "$run/log.txt"
    echo "$to" > "$run/exported"
    say "log exported, $(clock "$from") to $(clock "$to")"
  else
    say "log export failed; the next one covers its time"
  fi
  rm -f "$run/log.part"
}

# A sample every 5 minutes and an export every hour, by the wall clock: a slot missed while the Mac
# sleeps is taken on waking, not made up.
sample_loop() {
  local now next_sample next_export
  next_sample=$(date +%s)
  next_export=$(($(<"$run/exported") + export_every))
  while true; do
    now=$(date +%s)
    if ((now >= next_sample)); then
      keep_metrics_on || say "could not read the playback metrics switch"
      sample || say "sample failed"
      while ((next_sample <= now)); do next_sample=$((next_sample + sample_every)); done
    fi
    if ((now >= next_export)); then
      export_log
      next_export=$(($(<"$run/exported") + export_every))
      ((next_export > now)) || next_export=$((now + sample_every))
    fi
    sleep 10
  done
}

# MARK: Commands

cmd_start() {
  local dir="" since pid
  while (($#)); do
    case $1 in
      --dir) [[ $# -ge 2 ]] || usage; dir=$2; shift 2 ;;
      *) usage ;;
    esac
  done
  mkdir -p "$runs"
  if [[ -f $current ]]; then
    run=$(<"$current")
    if [[ -f $run/events.csv ]] && ! has_event end; then
      ! pid=$(sampler_pid) || fail "the soak in $run is running already (pid $pid)"
      [[ -z $dir || $(cd "$dir" 2>/dev/null && pwd) == "$run" ]] || fail "the soak in $run is not stopped: soak.sh stop first"
      say "carrying on the soak in $run"
      claim_run
      has_event start || wait_for_live "$(<"$run/exported")"
      sample_loop
      return
    fi
  fi
  if [[ -n $dir ]]; then
    mkdir -p "$dir"
    run=$(cd "$dir" && pwd)
  else
    run=$runs/$(date +%Y-%m-%d-%H%M)
  fi
  [[ ! -e $run/events.csv ]] || fail "$run holds a soak already"
  mkdir -p "$run"
  echo 'time,kind,note' > "$run/events.csv"
  echo 'time,process,pid,cpu,rss_kb' > "$run/samples.csv"
  : > "$run/log.txt"
  since=$(date +%s)
  echo "$since" > "$run/exported" # log.txt runs from here, so the live that starts the clock is in it
  echo "$run" > "$current"
  say "soak in $run"
  claim_run
  check_extension_copies
  wait_for_live "$since"
  sample_loop
}

cmd_mark() {
  local kind=${1:-} n
  case $kind in
    lid | replug | fus | drill | lock | note) shift ;;
    *) fail "mark takes lid, replug, fus, drill, lock or note" ;;
  esac
  open_run
  event "$kind" "$*"
  n=$(count_events "$kind")
  case $kind in
    lid)
      if ((n % 2)); then say "lid cycle $n of 20: close it, count 10 seconds, open it"
      else say "lid cycle $n of 20: close it for 2 minutes, then open it"; fi ;;
    replug)
      if ((n % 2)); then say "cable $n of 20: pull it, count 5 seconds, plug it back"
      else say "cable $n of 20: pull it for 30 seconds, then plug it back"; fi ;;
    fus) say "fast user switching: to the second account, 5 minutes there, then back" ;;
    drill) say "drill: ${*:-(unnamed)}. Its episodes are listed apart, for its row in the PR" ;;
    *) say "marked $kind" ;;
  esac
}

# Sleeps every 20 minutes between --from (default: a minute from now) and --to (default 07:00): 2
# minutes asleep and 18 awake, but once, mid-night, 30 minutes asleep (S4's long sleep). pmset
# schedules a wake only as root, so every wake is scheduled up front under one sudo; a wake that
# comes while the Mac is awake does nothing. pmset's wakes are imprecise (`man pmset`): the report
# times each wake from the log, not from this plan.
cmd_night() {
  local from="" to=07:00 start end t i n long wake note cmds="" sleeps=() wakes=()
  while (($#)); do
    case $1 in
      --from) [[ $# -ge 2 ]] || usage; from=$2; shift 2 ;;
      --to) [[ $# -ge 2 ]] || usage; to=$2; shift 2 ;;
      *) usage ;;
    esac
  done
  open_run
  if [[ -n $from ]]; then start=$(next_at "$from" "$(date +%s)"); else start=$(($(date +%s) + 60)); fi
  end=$(next_at "$to" "$start")
  n=$(((end - start) / 1200))
  ((n >= 1)) || fail "no room for a 20-minute cycle from $(clock "$start") to $(clock "$end")"
  long=$((n / 2))
  t=$start
  i=0
  while ((t + 120 <= end)); do
    sleeps+=("$t")
    if ((i == long)); then wake=$((t + 1800)); else wake=$((t + 120)); fi
    wakes+=("$wake")
    cmds+="pmset schedule wake \"$(date -r "$wake" '+%m/%d/%y %H:%M:%S')\"; "
    t=$((wake + 1080))
    i=$((i + 1))
  done
  say "the night: ${#sleeps[@]} sleeps, $(date -r "$start" '+%a %H:%M') to $(date -r "${sleeps[i - 1]}" +%H:%M);" \
    "the one at $(date -r "${sleeps[long]}" +%H:%M) lasts 30 minutes, the others 2"
  say "pmset schedules a wake only as root: sudo asks once, for all of them"
  sudo /bin/sh -c "set -e; $cmds" || fail "the wakes were not scheduled"
  trap 'say "night stopped; the wakes still scheduled wake an awake Mac, which does nothing (pmset -g sched)"; exit 130' INT TERM
  for i in "${!sleeps[@]}"; do
    wait_until "${sleeps[i]}"
    if (($(date +%s) >= wakes[i] - 30)); then
      say "skipped the sleep at $(clock "${sleeps[i]}"): its wake, $(clock "${wakes[i]}"), has passed"
      continue
    fi
    note="wake planned $(clock "${wakes[i]}")"
    if ((i == long)); then note+=" (the long sleep)"; fi
    event sleep "$note"
    say "sleeping, $note"
    pmset sleepnow > /dev/null
  done
  say "the night is done"
}

cmd_displaysleep() {
  local count=${1:-10} i=1
  [[ $count =~ ^[0-9]+$ ]] || usage
  open_run
  if [[ $(screen_lock) == "delay is immediate" ]]; then
    say "the password is asked for at once, so each wake shows the lock screen: unlock when this is done"
  fi
  while ((i <= count)); do
    event displaysleep "$i of $count"
    say "display sleep $i of $count"
    pmset displaysleepnow > /dev/null
    sleep 30
    caffeinate -u -t 5 # user activity, as a key press would be: the display wakes
    sleep 60
    i=$((i + 1))
  done
  say "display sleep done"
}

# "screenLock delay is immediate", "screenLock is off" or "screenLock delay is <n> seconds", less the first word.
screen_lock() { sysadminctl -screenLock status 2>&1 | sed -n 's/.*screenLock //p'; }

# The session dictionary carries the key only while the screen is locked (LockSensor.swift).
is_locked() { [[ $(ioreg -n Root -d1) == *'"CGSSessionScreenIsLocked"=Yes'* ]]; }

wait_for_unlock() {
  say "waiting for the unlock"
  while is_locked; do sleep 2; done
  say "unlocked"
}

# The screen saver with the password asked for at once, then `caffeinate -u` to show the lock screen:
# the locked surface with nobody at the keyboard. Two of the spec's ten are a person's with
# ctrl-cmd-Q (`lock --person`), so the script does eight.
cmd_lock() {
  local count i=1 waited=0
  open_run
  if [[ ${1:-} == --person ]]; then
    event lock "ctrl-cmd-Q"
    say "lock the Mac now with ctrl-cmd-Q, leave it about 30 seconds, then unlock"
    until is_locked; do
      sleep 1
      waited=$((waited + 1))
      ((waited < 120)) || fail "no lock in 2 minutes"
    done
    wait_for_unlock
    return
  fi
  count=${1:-8}
  [[ $count =~ ^[0-9]+$ ]] || usage
  [[ $(screen_lock) == "delay is immediate" ]] ||
    say "warning: the password is not asked for at once (Lock Screen settings), so the screen saver will not lock"
  while ((i <= count)); do
    event lock "screen saver $i of $count"
    say "lock $i of $count: the screen saver now, the lock screen in 30 seconds; then unlock"
    open -a ScreenSaverEngine
    sleep 30
    is_locked || say "warning: the session did not lock"
    caffeinate -u -t 5
    wait_for_unlock
    sleep 30 # the check after the unlock has its grace before the next lock
    i=$((i + 1))
  done
  say "lock done: the other two of the ten are a person's, soak.sh lock --person, twice"
}

cmd_stop() {
  local pid waited=0 started report
  find_run
  if ! has_event end; then
    if pid=$(sampler_pid); then
      say "stopping the soak's start (pid $pid)"
      kill -TERM "$pid"
      while sampler_pid > /dev/null; do
        sleep 1
        waited=$((waited + 1))
        ((waited < 120)) || fail "the soak's start (pid $pid) did not stop"
      done
    fi
    event end
    export_log
  fi
  [[ -x $here/soak-report ]] || fail "Tools/soak/soak-report is missing; the run is in $run"
  started=$(first_time start)
  started=${started:0:10}
  [[ -n $started ]] || started=$(date +%Y-%m-%d)
  report=$repo/docs/reports/soak-$started.md
  "$here/soak-report" soak --log "$run/log.txt" --samples "$run/samples.csv" --events "$run/events.csv" \
    > "$run/report.md" || fail "soak-report failed; the run is in $run"
  mkdir -p "$(dirname "$report")"
  cp "$run/report.md" "$report"
  say "the run: $run (events.csv, samples.csv, log.txt)"
  say "the report: $report"
  say "the raw log goes on the pr-media branch (Tools/pr-media/publish.sh), never into master"
}

cmd_status() {
  local started ended start finish pid
  find_run
  started=$(first_time start)
  ended=$(first_time end)
  echo "run        $run"
  if [[ -z $started ]]; then
    echo "started    not yet: waiting for the host's first live"
  else
    start=$(epoch_of "$started")
    if [[ -n $ended ]]; then finish=$(epoch_of "$ended"); else finish=$(date +%s); fi
    echo "started    $started"
    [[ -z $ended ]] || echo "ended      $ended"
    echo "elapsed    $(duration $((finish - start)))"
  fi
  if pid=$(sampler_pid); then echo "sampling   pid $pid"; else echo "sampling   not running"; fi
  echo "samples    $(sample_count)"
  awk -F, 'NR > 1 { if ($1 != t) { t = $1; s = "" } s = s "  " $2 " " $4 "% " int($5 / 1024) " MB" }
    END { if (t != "") print "last       " t ":" s }' "$run/samples.csv"
  echo "metrics    $(notifyutil -g "$metrics" | awk '{ print ($NF == 1 ? "on" : "off") }')"
  echo "log        $(wc -c < "$run/log.txt" | awk '{ printf "%.1f MB", $1 / 1048576 }'), exported to $(clock "$(<"$run/exported")")"
  echo "events"
  awk -F, 'NR > 1 { n[$2]++ } END { for (kind in n) printf "  %-13s %d\n", kind, n[kind] }' "$run/events.csv" | sort
  echo "last events"
  awk 'NR > 1' "$run/events.csv" | tail -n 5 | sed 's/^/  /'
}

command=${1:-}
[[ $# -eq 0 ]] || shift
case $command in
  start) cmd_start "$@" ;;
  mark) cmd_mark "$@" ;;
  night) cmd_night "$@" ;;
  displaysleep) cmd_displaysleep "$@" ;;
  lock) cmd_lock "$@" ;;
  stop) [[ $# -eq 0 ]] || usage; cmd_stop ;;
  status) [[ $# -eq 0 ]] || usage; cmd_status ;;
  *) usage ;;
esac
