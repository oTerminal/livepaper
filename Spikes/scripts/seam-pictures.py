#!/usr/bin/env python3
"""Reads an S2 result (probe=2) on stdin and prints which pictures were on screen around each seam."""
import json, sys
d = json.load(sys.stdin)
per_pass = int(sys.argv[1])
fps = round(1 / d["frameDuration"])
trace = d["changes"]
print(f"  {d['clip']}: {len({int(p) for _,_,p in trace})} distinct pictures seen, renderer dropped {d['droppedFrames']}/{d['totalFrames']}")
for seam in range(1, d["loops"]):
    at = seam * per_pass / fps
    window = [(t, ms, int(p)) for t, ms, p in trace if at - 0.12 < t < at + 0.2]
    print(f"  seam {seam} (t={at:.3f}): " + "  ".join(f"#{p}@{t - at:+.3f}{'!' if ms > 1500 * d['frameDuration'] else ''}" for t, ms, p in window))
