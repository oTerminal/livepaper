#!/bin/bash
# Averages CPU % and top's "POWER" score (energy impact, unitless) for some processes.
# powermetrics would give watts but needs root; this does not.
#
#   measure.sh <seconds> <name-or-pid>...      e.g. measure.sh 30 LivepaperExtension WindowServer
set -euo pipefail
SECONDS_TOTAL=$1; shift
SAMPLES=$(( SECONDS_TOTAL / 5 ))
# The first top sample has no deltas, so take one extra and drop it.
top -l $(( SAMPLES + 1 )) -s 5 -stats pid,command,cpu,power 2>/dev/null | awk -v want="$*" '
  BEGIN { n = split(want, names, " ") }
  /^PID/ { sample++ ; next }
  sample > 1 {
    # top truncates long command names, so compare against the same truncation.
    for (i = 1; i <= n; i++) if ($1 == names[i] || $2 == names[i] || $2 == substr(names[i], 1, length($2)) && length($2) >= 15) { cpu[names[i]] += $(NF-1); power[names[i]] += $NF; seen[names[i]]++ }
  }
  END { for (i = 1; i <= n; i++) if (seen[names[i]]) printf "  %-22s cpu %6.2f %%   power %7.2f   (%d samples)\n", names[i], cpu[names[i]] / (sample - 1), power[names[i]] / (sample - 1), sample - 1
        else if (n) for (i = 1; i <= n; i++) if (!seen[names[i]]) printf "  %-22s not seen\n", names[i] }'
