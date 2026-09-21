# Run sheet

M1 is closed. S0, S0b (gate G1) and S0c were run by a person and passed; everything else that could be
run was run by the spike (`results/`). What was left needed hardware or patience a spike should not
demand, so it moved to where it is looked at anyway:

| Row | Goes to |
|---|---|
| S3: second display, Spaces, fullscreen, Stage Manager, replug | M5 (built against one display, keyed by display UUID), checked in M8. An extended AirPlay display is enough to try it; its UUID may not be stable across sessions, which says nothing about real monitors |
| S3: two identical monitors, cable swaps | Dropped. If a user hits it, it is a bug report |
| S4: 20 lid cycles, 30-minute sleep, fast user switching | M8's soak test |
| S5 and S7, eyes-on halves; S6 lock transitions | M5, when the real engine is on screen |

## One optional check (2 minutes, no extra hardware)

Sleep/wake was Wallper's worst recurring bug, so it is worth knowing early. All commands from `Spikes/`.

1. Open `/Applications/Livepaper.app`, choose "Livepaper" in System Settings > Wallpaper.
2. `scripts/lp config mode=video video=a-1080p30-h264.mp4`
3. Close the lid, wait ten seconds, open it. Is the video moving within 2 s?
4. Lock (ctrl-cmd-Q): is it playing on the lock screen? Any grey flash going in or coming out?

If nothing shows, `killall WallpaperAgent` once and look again (`results/S0.md`, "Hazard").

## When done

`scripts/cleanup.sh`, then pick your old wallpaper in System Settings > Wallpaper.
