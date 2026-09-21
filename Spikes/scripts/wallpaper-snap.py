#!/usr/bin/env python3
"""Throwaway spike tool (S3). Needs Screen Recording.  wallpaper-snap.py <label>: capture every wallpaper window 3 times over ~1.5 s (the window itself, so nothing covers it);
say which clip each shows and whether the picture moves. Also keeps one small full-display capture per display."""
import subprocess, sys, time, os
from collections import Counter
from PIL import Image, ImageChops
here = os.path.dirname(os.path.abspath(__file__))
label = sys.argv[1]
out = os.path.join(here, "..", "build", "s3"); os.makedirs(out, exist_ok=True)
tool = os.path.join(out, "wallpaper-windows")
if not os.path.exists(tool): subprocess.run(["swiftc", "-O", f"{here}/wallpaper-windows.swift", "-o", tool], check=True)
wins = [l.split() for l in subprocess.run([tool], capture_output=True, text=True).stdout.splitlines()]
here = out  # captures land in build/s3, never in the repo
def cap(args, p):
    subprocess.run(["screencapture", "-x", *args, p], check=False, capture_output=True)
    return Image.open(p).convert("RGB") if os.path.exists(p) else None
def clip(rgb):
    r, g, b = rgb
    if r > 180 and g < 100 and b < 100: return "A"
    if g > 90 and r < 90 and b < 110: return "B"
    if max(rgb) - min(rgb) < 25: return f"GREY{rgb}"
    return f"?{rgb}"
shots = {w[0]: [] for w in wins}
for i in range(3):
    for w in wins: shots[w[0]].append(cap(["-o", "-l", w[0]], f"{here}/{label}-w{w[0]}-{i}.png"))
    time.sleep(0.6)
for w in wins:
    wid, x, y, ww, hh, on = w
    s = shots[wid]
    if any(v is None for v in s): print(f"wallpaper window {wid} at {x},{y} {ww}x{hh} onscreen={on}: no capture"); continue
    a = s[0]; W, H = a.size
    votes = Counter(clip(a.getpixel((int(W * 0.02), int(H * fy)))) for fy in (0.2, 0.4, 0.6, 0.8, 0.95))
    changed = 0
    for b in s[1:]:
        d = ImageChops.difference(a, b).convert("L")
        changed += sum(1 for v in d.tobytes() if v > 12)
    print(f"wallpaper window {wid} at {x},{y} {ww}x{hh} onscreen={on} ({W}x{H} px): clip votes {dict(votes)}; changed pixels over 3 captures: {changed} -> {'MOVING' if changed > 500 else 'STILL'}")
    a.resize((700, 700 * H // W)).save(f"{here}/{label}-w{wid}-small.png")
    for i in range(3): os.remove(f"{here}/{label}-w{wid}-{i}.png")
for n in (1, 2):
    p = f"{here}/{label}-d{n}.png"
    full = cap(["-D", str(n)], p)
    if full is None: print(f"display {n}: no full capture"); continue
    W, H = full.size
    full.resize((900, 900 * H // W)).save(f"{here}/{label}-d{n}-small.png"); os.remove(p)
