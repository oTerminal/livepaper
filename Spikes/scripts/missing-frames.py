#!/usr/bin/env python3
"""Reads an S2 result JSON on stdin and lists the frames the probe never saw displayed."""
import json, sys
d = json.load(sys.stdin)
fps = round(1 / d["frameDuration"])
per_pass = int(sys.argv[1]) if len(sys.argv) > 1 else 5 * fps
frame_ms = 1000 * d["frameDuration"]
trace = d["changes"]
index = round(trace[0][0] * fps)
missing = []
# A change that arrives n frame durations after the previous one skipped n - 1 frames.
for t, interval, *_ in trace[1:]:
    steps = max(1, round(interval / frame_ms)) if interval < 1000 else 1
    missing += range(index + 1, index + steps)
    index += steps
if d.get("occludedSeconds"): print(f"  window occluded for {d['occludedSeconds']:.0f} s (ignored by the probe)")
print(f"  {d['clip']} [decoder reset: {d.get('decoderReset')}, {d.get('markerBuffersSkipped')} markers skipped]: loops {d['loops']} ({d.get('seamsObserved')} seams observed), renderer dropped {d['droppedFrames']}/{d['totalFrames']}, "
      f"seam step {d['maxSeamStep']:.3f}, min seam lead {d['minSeamLead']:.2f} s, "
      f"max presented gap {d['maxPresentedGap']:.2f} frames, over 1.5: {d['presentedGapsOverLimit']}")
print("  frames never displayed:", [(f, f"pass {f // per_pass} + {f % per_pass}") for f in missing[:12]] or "none")
