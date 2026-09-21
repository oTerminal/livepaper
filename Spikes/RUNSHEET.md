# Run sheet

M1 is closed. S0, S0b (gate G1) and S0c were run by a person and passed; everything else that could be
run was run by the spike (`results/`). What was left needed hardware or patience a spike should not
demand, so it moved to where it is looked at anyway:

| Row | Goes to |
|---|---|
| S3: second display, Spaces, fullscreen, Stage Manager, resolution, replug, lock with two displays | Run 2026-09-21 with a real monitor: `results/S3.md`. Two things for M5: a covered display reports no displayed pictures, and a mode change stretches the surface |
| S3: two identical monitors, cable swaps | Dropped. If a user hits it, it is a bug report |
| S4: 20 lid cycles, 30-minute sleep, fast user switching | M8's soak test |
| S5 and S7, eyes-on halves; S6 lock transitions | M5, when the real engine is on screen |

## The first check (2 minutes, no extra hardware): done, `results/S4.md`

Playback not resuming after sleep is the bug Wallper's users reported most often (`docs/roadmap.md`), so it is worth knowing early. All commands from `Spikes/`.

1. Open `/Applications/Livepaper.app`, choose "Livepaper" in System Settings > Wallpaper.
2. `scripts/lp config mode=video video=a-1080p30-h264.mp4`
3. Close the lid, wait ten seconds, open it. Is the video moving within 2 s?
4. Lock (ctrl-cmd-Q): is it playing on the lock screen? Any grey flash going in or coming out?

If nothing shows, `killall WallpaperAgent` once and look again (`results/S0.md`, "Hazard").

## The second check (2 minutes, needs the external monitor): done, `results/S3.md`

Start with different clips on the two displays (`results/S3.md` has the command; clip A has a red first bar,
clip B a green one).

1. Pull the monitor's cable, count to five, plug it back. Does the monitor come back on its own clip, moving?
2. Pull it again, wait 30 seconds (the extension tears an abandoned surface down after 15), plug it back. Same question.
3. Lock (ctrl-cmd-Q) with both attached: video on both lock screens? Any grey flash on either, going in or coming out?
4. `scripts/logs.sh show 10m | grep -E "ACQUIRE|INVALIDATE|teardown|s4:"` and keep the output: the display UUID
   after each `ACQUIRE` must be the one from before.

## When done

`scripts/cleanup.sh`, then pick your old wallpaper in System Settings > Wallpaper.
