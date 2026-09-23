#!/usr/bin/env python3
"""S10 energy runs, S2's method: for each case, set the spike's mode, warm up 15 s, then six 5 s
samples of `top -stats pid,command,cpu,power` (the first sample, which has no deltas, dropped),
with the GPU's "Device Utilization %" from ioreg once a second over the same 30 s.

    energy.py <round-label> <case>...      cases: video videoPaused freeze light60 light30 heavy60 heavy30

Before each run it waits until no build or render process of the other agents runs; a run during
which one appears is discarded and taken again. Each run is one JSON line in energy/runs.jsonl.
"""
import json
import os
import re
import subprocess
import sys
import threading
import time

S = "/private/tmp/claude-501/-Users-vaibhavprakash-Programming-livepaper/75d00fd0-b01c-4036-b5e7-832dec946c51/scratchpad/s10"
OUT = os.path.join(S, "energy")
os.makedirs(OUT, exist_ok=True)
WORDS = {
    "video": 0, "videoPaused": 4, "freeze": 3,
    "light60": 1 | 60 << 4, "light30": 1 | 30 << 4,
    "heavy60": 2 | 60 << 4, "heavy30": 2 | 30 << 4,
}
OTHERS = "swift-build|swift-test|ffmpeg|xcodebuild|ScenePipeline"
WARMUP, SAMPLES, PERIOD = 15, 6, 5


def sh(*args):
    return subprocess.run(args, capture_output=True, text=True).stdout


def others_running():
    return sh("pgrep", "-fl", OTHERS).strip()


def set_mode(word):
    subprocess.run(["notifyutil", "-s", "app.livepaper.s10", str(word)], check=True)
    subprocess.run(["notifyutil", "-p", "app.livepaper.s10"], check=True)


def extension_pid():
    out = sh("pgrep", "-f", "build/Frozen/Livepaper.app/Contents/Extensions/WallpaperExtension").split()
    return out[0] if out else None


def gpu_util():
    m = re.search(r'"Device Utilization %"=(\d+)', sh("ioreg", "-r", "-d", "1", "-w", "0", "-c", "IOAccelerator"))
    return int(m.group(1)) if m else None


def idle_seconds():
    m = re.search(r'"HIDIdleTime" = (\d+)', sh("ioreg", "-c", "IOHIDSystem"))
    return int(m.group(1)) / 1e9 if m else None


def coverage():
    return float(sh(os.path.join(S, "coverage")).strip() or "nan")


def loadavg():
    return sh("sysctl", "-n", "vm.loadavg").strip().strip("{} ")


def measure(ext_pid):
    """Six 5 s top samples and 1 s GPU samples; the other agents' processes watched throughout."""
    gpu, seen_others, stop = [], [], threading.Event()

    def sampler():
        while not stop.is_set():
            value = gpu_util()
            if value is not None:
                gpu.append(value)
            found = others_running()
            if found:
                seen_others.append(found)
            stop.wait(1)

    thread = threading.Thread(target=sampler)
    thread.start()
    top = sh("top", "-l", str(SAMPLES + 1), "-s", str(PERIOD), "-stats", "pid,command,cpu,power")
    stop.set()
    thread.join()
    groups = {"ext": [], "WindowServer": [], "WallpaperAgent": [], "VTDecoder": [], "avconferenced": [], "Livepaper": []}
    sample, per = 0, None
    cpu_user_sys = []
    for line in top.splitlines():
        if line.startswith("CPU usage:") and sample >= 1:
            m = re.findall(r"([\d.]+)% (user|sys)", line)
            cpu_user_sys.append(sum(float(v) for v, _ in m))
        if line.startswith("PID"):
            if per is not None and sample > 1:
                for k, v in per.items():
                    groups[k].append(v)
            sample += 1
            per = {k: [0.0, 0.0] for k in groups}
            continue
        if per is None or sample <= 1:
            continue
        parts = line.split()
        if len(parts) < 4:
            continue
        pid, cpu, power = parts[0], parts[-2], parts[-1]
        name = " ".join(parts[1:-2])
        try:
            cpu, power = float(cpu), float(power)
        except ValueError:
            continue
        key = None
        if pid == ext_pid:
            key = "ext"
        elif name == "WindowServer":
            key = "WindowServer"
        elif name.startswith("WallpaperAgent"):
            key = "WallpaperAgent"
        elif name.startswith("VTDecoderXPCServ"):
            key = "VTDecoder"
        elif name.startswith("avconferenced"):
            key = "avconferenced"
        elif name == "Livepaper":
            key = "Livepaper"
        if key:
            per[key][0] += cpu
            per[key][1] += power
    if per is not None and sample > 1:
        for k, v in per.items():
            groups[k].append(v)
    result = {}
    for k, values in groups.items():
        if values:
            result[k] = {
                "cpu": round(sum(v[0] for v in values) / len(values), 2),
                "power": round(sum(v[1] for v in values) / len(values), 2),
                "n": len(values),
            }
    result["gpu"] = {
        "mean": round(sum(gpu) / len(gpu), 1) if gpu else None,
        "min": min(gpu) if gpu else None,
        "max": max(gpu) if gpu else None,
        "n": len(gpu),
    }
    result["systemCpu"] = round(sum(cpu_user_sys) / max(1, len(cpu_user_sys)), 1) if cpu_user_sys else None
    return result, seen_others


def wait_for_quiet(quiet=20):
    """Until none of the other agents' processes has been seen for `quiet` seconds."""
    calm_since, reported = time.time(), 0.0
    while time.time() - calm_since < quiet:
        found = others_running()
        if found:
            calm_since = time.time()
            if time.time() - reported > 60:
                print(f"  waiting for other load: {found.splitlines()[0][:120]!r}", flush=True)
                reported = time.time()
        time.sleep(2)


def run_case(label, case):
    for attempt in range(1, 11):
        wait_for_quiet()
        ext = extension_pid()
        set_mode(WORDS[case])
        time.sleep(WARMUP)
        start = time.time()
        before = {"load": loadavg(), "idle": idle_seconds(), "coverage": coverage()}
        result, seen = measure(ext)
        after = {"load": loadavg(), "idle": idle_seconds(), "coverage": coverage()}
        record = {
            "round": label, "case": case, "attempt": attempt, "start": time.strftime("%H:%M:%S", time.localtime(start)),
            "end": time.strftime("%H:%M:%S"), "ext_pid": ext, "before": before, "after": after,
            "discarded": bool(seen), "others": seen[:3], **result,
        }
        with open(os.path.join(OUT, "runs.jsonl"), "a") as f:
            f.write(json.dumps(record) + "\n")
        g = result.get
        print(
            f"{label} {case:12s} {record['start']}-{record['end']} ext {g('ext', {}).get('cpu')}%/{g('ext', {}).get('power')} "
            f"WS {g('WindowServer', {}).get('cpu')}%/{g('WindowServer', {}).get('power')} "
            f"VTD {g('VTDecoder', {}).get('cpu')}%/{g('VTDecoder', {}).get('power')} "
            f"WA {g('WallpaperAgent', {}).get('cpu')}%/{g('WallpaperAgent', {}).get('power')} "
            f"GPU {result['gpu']['mean']}% ({result['gpu']['min']}-{result['gpu']['max']}) "
            f"sys {result['systemCpu']}% avconf {g('avconferenced', {}).get('cpu')}% "
            f"load {before['load']} idle {before['idle']:.0f}s cov {before['coverage']}"
            + ("  DISCARDED" if seen else ""),
            flush=True,
        )
        if not seen:
            return record
    return None


if __name__ == "__main__":
    label = sys.argv[1]
    for case in sys.argv[2:]:
        run_case(label, case)
