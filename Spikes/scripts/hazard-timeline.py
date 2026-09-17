#!/usr/bin/env python3
"""Summarises results/raw/hazard-timeline.log: every time pkd asked launchd to remove the
extension's instances (it does so on every launch of the host app), whether one was found,
and every extension start. Regenerate the log with the `log show` command in results/S0.md."""
import re, sys
rows = []
for line in open(sys.argv[1] if len(sys.argv) > 1 else "results/raw/hazard-timeline.log"):
    m = re.match(r"\S+ (\d\d:\d\d:\d\d)\.\d+ ", line)
    if not m:
        continue
    t = m.group(1)
    if "total of 1 extension" in line:
        rows.append((t, "REMOVED the running extension"))
    elif "total of 0 extension" in line:
        rows.append((t, "ok"))
    elif "nterruptionHandler called" in line:
        rows.append((t, "  WallpaperAgent: interruptionHandler called"))
    elif "extension: INIT" in line:
        build = re.search(r"build (\d+)", line).group(1)
        where = "/Applications" if "/Applications" in line else "DerivedData"
        rows.append((t, f"extension started (build {build}, {where})"))
run, first, last = 0, None, None
for t, kind in rows:
    if kind == "ok":
        run, first, last = run + 1, first or t, t
        continue
    if run:
        print(f"{first}-{last}  {run} host-app launches, nothing removed")
        run, first = 0, None
    print(f"{t}  {kind}")
if run:
    print(f"{first}-{last}  {run} host-app launches, nothing removed")
