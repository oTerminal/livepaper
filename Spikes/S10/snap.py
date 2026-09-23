#!/usr/bin/env python3
"""snap.py <label>: captures the desktop's wallpaper window (the window only, by id) twice, 0.5 s
apart, says how much of it changed, and keeps a small copy of the first capture to look at."""
import os
import subprocess
import sys
import time

from PIL import Image, ImageChops

S = "/private/tmp/claude-501/-Users-vaibhavprakash-Programming-livepaper/75d00fd0-b01c-4036-b5e7-832dec946c51/scratchpad/s10"
label = sys.argv[1]
out = os.path.join(S, "shots")
os.makedirs(out, exist_ok=True)
wid = subprocess.run([os.path.join(S, "winid"), "--desktop"], capture_output=True, text=True).stdout.split()[0]
paths = []
for i in range(2):
    p = os.path.join(out, f"{label}-{i}.png")
    subprocess.run(["screencapture", "-x", "-o", "-l", wid, p], check=True)
    paths.append(p)
    time.sleep(0.5)
a, b = (Image.open(p).convert("RGB") for p in paths)
d = ImageChops.difference(a, b).convert("L")
changed = sum(1 for v in d.tobytes() if v > 12)
print(f"window {wid} {a.size[0]}x{a.size[1]}: {changed} of {a.size[0] * a.size[1]} pixels changed in 0.5 s "
      f"({100 * changed / (a.size[0] * a.size[1]):.1f} %)")
small = os.path.join(out, f"{label}-small.png")
a.resize((900, 900 * a.size[1] // a.size[0])).save(small)
os.remove(paths[1])
print(small)
