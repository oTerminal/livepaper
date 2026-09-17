#!/bin/bash
# Streams what the spec asks every row to record: WallpaperAgent, pkd and amfid lines
# that mention the spike, plus everything the spike itself logs.
#
#   logs.sh                 stream until ctrl-c
#   logs.sh show 5m         the same predicate over the last 5 minutes
PREDICATE='subsystem == "app.livepaper.spike"
  OR (process == "LivepaperExtension" AND subsystem == "com.apple.extensionkit")
  OR (process == "launchd" AND eventMessage CONTAINS "app.livepaper.spike.extension" AND eventMessage CONTAINS "instances")
  OR (process IN {"pkd", "amfid", "WallpaperAgent", "syspolicyd", "taskgated-helper", "sandboxd", "kernel"}
      AND eventMessage CONTAINS[c] "livepaper")
  OR (process == "tccd" AND eventMessage CONTAINS[c] "livepaper" AND eventMessage CONTAINS[c] "prompt")'
if [ "${1:-}" = show ]; then
  log show --last "${2:-5m}" --style compact --info --predicate "$PREDICATE"
else
  # exec, so that killing this script's pid stops the stream itself
  exec log stream --style compact --level info --predicate "$PREDICATE"
fi
