#!/usr/bin/env python3
"""S10 stop and restart: one-second samples of top and of the GPU's utilisation around an event.

    timeline.py <label> <case> <event> [before=10] [during=30] [after=15]

The spike's mode is set to <case> (as in energy.py), 15 s of warm-up follow, then sampling starts;
<before> seconds later the event begins and lasts <during> seconds:

    cover         the covering window (cover.swift), ordered behind every other window; the app,
                  which must be running, senses it and the extension pauses
    inj-asleep    the app is not running; render-state.json is written as the app writes it, with
                  the display asleep, then again every 10 s, then with nothing sensed
    inj-covered   the same with the display covered

Prints a row a second (t relative to the event's start) and the extension's and the app's log lines
over the same time, and appends the lot to energy/timeline-<label>.txt.
"""
import json
import os
import re
import subprocess
import sys
import threading
import time
from datetime import datetime

S = "/private/tmp/claude-501/-Users-vaibhavprakash-Programming-livepaper/75d00fd0-b01c-4036-b5e7-832dec946c51/scratchpad/s10"
LIBRARY = os.path.expanduser("~/Library/Application Support/Livepaper")
DISPLAY = "37D8832A-2D66-02CA-B9F7-8F30A301B230"
REFERENCE = 978307200  # 2001-01-01 in Unix time: Foundation's Date encoding

sys.path.insert(0, S)
import energy  # noqa: E402

label, case, event = sys.argv[1], sys.argv[2], sys.argv[3]
before, during, after = (int(v) for v in (sys.argv[4:7] + ["10", "30", "15"][len(sys.argv[4:7]):]))
total = before + during + after
out_lines = []


def say(line):
    print(line, flush=True)
    out_lines.append(line)


def app_running():
    return bool(energy.sh("pgrep", "-f", "Livepaper.app/Contents/MacOS/Livepaper").strip())


def write_state(asleep=False, covered=False):
    path = os.path.join(LIBRARY, "render-state.json")
    with open(path) as f:
        state = json.load(f)
    state["generation"] = state["generation"] + 1
    state["stopped"] = False
    state["conditions"] = {
        "asleepDisplays": [DISPLAY] if asleep else [],
        "coveredDisplays": [DISPLAY] if covered else [],
        "locked": False, "lowPowerMode": False, "onBattery": False,
        "sensedAt": time.time() - REFERENCE,
    }
    temporary = path + ".s10"
    with open(temporary, "w") as f:
        json.dump(state, f, indent=2, sort_keys=True)
    os.replace(temporary, path)
    subprocess.run(["notifyutil", "-p", "app.livepaper.render-state"], check=True)
    return state["generation"]


if event == "cover" and not app_running():
    sys.exit("cover needs the app running: it senses the window")
if event.startswith("inj-") and app_running():
    sys.exit("an injected condition needs the app quit: it writes render-state.json")

while energy.others_running():
    say(f"waiting for other load: {energy.others_running()!r}")
    time.sleep(10)

if event.startswith("inj-"):
    say(f"render state written, nothing sensed, generation {write_state()}")
ext = energy.extension_pid()
energy.set_mode(energy.WORDS[case])
time.sleep(energy.WARMUP)

gpu, others, stop = [], [], threading.Event()


def sampler():
    while not stop.is_set():
        value = energy.gpu_util()
        if value is not None:
            gpu.append((time.time(), value))
        found = energy.others_running()
        if found:
            others.append(found)
        stop.wait(0.5)


def run_event(start):
    time.sleep(max(0, start - time.time()))
    if event == "cover":
        helper = subprocess.Popen([os.path.join(S, "cover"), str(during), "back"], stdout=subprocess.PIPE, text=True)
        for line in helper.stdout:
            say(f"cover: {line.strip()}")
        helper.wait()
        if helper.returncode == 2:
            say("cover: CLICKED, run disturbed")
    else:
        asleep, covered = event == "inj-asleep", event == "inj-covered"
        end = start + during
        while time.time() < end:
            say(f"{datetime.now():%H:%M:%S.%f}"[:-3] + f" render state written, {event[4:]}, generation {write_state(asleep, covered)}")
            time.sleep(min(10, max(0, end - time.time())))
        say(f"{datetime.now():%H:%M:%S.%f}"[:-3] + f" render state written, nothing sensed, generation {write_state()}")


t0 = time.time()
event_start = t0 + before + 1
threading.Thread(target=sampler).start()
event_thread = threading.Thread(target=run_event, args=(event_start,))
event_thread.start()
load = energy.loadavg()
top = energy.sh("top", "-l", str(total + 2), "-s", "1", "-stats", "pid,command,cpu,power")
stop.set()
event_thread.join()

rows, when, per = [], None, None
for line in top.splitlines():
    m = re.match(r"(\d{4}/\d\d/\d\d \d\d:\d\d:\d\d)", line)
    if m:
        if per is not None and when is not None:
            rows.append((when, per))
        when = datetime.strptime(m.group(1), "%Y/%m/%d %H:%M:%S").timestamp()
        per = {"ext": [0.0, 0.0], "WS": [0.0, 0.0], "VTD": [0.0, 0.0]}
        continue
    parts = line.split()
    if per is None or len(parts) < 4 or not parts[0].isdigit():
        continue
    try:
        cpu, power = float(parts[-2]), float(parts[-1])
    except ValueError:
        continue
    name = " ".join(parts[1:-2])
    key = "ext" if parts[0] == ext else "WS" if name == "WindowServer" else "VTD" if name.startswith("VTDecoderXPCServ") else None
    if key:
        per[key][0] += cpu
        per[key][1] += power
if per is not None and when is not None:
    rows.append((when, per))
rows = rows[1:]  # the first sample has no deltas

say(f"== {label} {case} {event}: before {before} s, during {during} s, after {after} s; event at "
    f"{datetime.fromtimestamp(event_start):%H:%M:%S}; load {load}; ext pid {ext}; others {others[:2] if others else 'none'}")
say("   t  ext cpu  ext pwr   WS cpu   WS pwr  VTD cpu  GPU %")
for stamp, per in rows:
    t = stamp - event_start
    samples = [v for (s, v) in gpu if stamp - 1 < s <= stamp]
    g = sum(samples) / len(samples) if samples else float("nan")
    say(f"{t:4.0f} {per['ext'][0]:8.1f} {per['ext'][1]:8.1f} {per['WS'][0]:8.1f} {per['WS'][1]:8.1f} {per['VTD'][0]:8.1f} {g:6.0f}")

since = datetime.fromtimestamp(t0 - 2).strftime("%Y-%m-%d %H:%M:%S")
logs = subprocess.run(
    ["/usr/bin/log", "show", "--start", since, "--style", "compact", "--predicate", 'subsystem BEGINSWITH "app.livepaper"'],
    capture_output=True, text=True,
).stdout
for line in logs.splitlines():
    if re.search(r"s10: (loop|mode|metal layer|first)|decision|sensing:|holding|now showing|render state read", line):
        say(line[11:23] + " " + re.sub(r"^.*?\] ", "", line)[:220])

with open(os.path.join(S, "energy", f"timeline-{label}.txt"), "a") as f:
    f.write("\n".join(out_lines) + "\n\n")
