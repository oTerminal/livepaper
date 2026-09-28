# Soak tooling

The scripts behind M8's soak, energy suite and hot-plug loop. [M8-hardening.md](../../docs/specs/M8-hardening.md) is the authority on what is run, how often and what passes; this page gives only the order and where the output goes. `soak.sh`, `energy.sh` and `display-mode.swift` print their usage when run with no arguments.

| Script | Does |
|---|---|
| `clips.sh` | Makes the 1080p60 and 4K60 HEVC test clips, frame counter burned in, in `build/soak-clips/` |
| `soak.sh` | Drives the 24-hour soak and keeps its record: `start`, `mark`, `night`, `displaysleep`, `lock`, `status`, `stop` |
| `energy.sh` | S2's energy suite on product code: `video`, `scene`, `idle` |
| `display-mode.swift` | `list` shows every display's ID, UUID and modes; `set` changes one for this login session |
| `soak-report` | Turns a soak's or a suite's record into the report |

## A soak

1. A stable install: one copy of the extension (`pluginkit -m -v -i app.livepaper.Livepaper.WallpaperExtension` lists one), and no bundle replaced from here to the end.
2. `Tools/soak/clips.sh`, then import six wallpapers in the library window: the two bundled CC0 samples, the two clips, one of your own with audio, and one Workshop scene.
3. The built-in display shows a playlist of all six, shuffled, every 5 minutes and on wake. The external shows the 4K60 clip.
4. `Tools/soak/soak.sh start`, in a terminal left open, or `nohup Tools/soak/soak.sh start > ~/soak.out 2>&1 &`, then quit Livepaper and open it again. The soak's clock starts at the host's live, which the report reads from the log `start` exports, so a Livepaper live already must go live once more. From then it keeps Log Playback Metrics on, samples every 5 minutes, exports the log every hour, and holds `caffeinate -i` so that the Mac never idle-sleeps. If it is stopped by accident, `soak.sh start` again carries on the same run.
5. The scripted rows, from another terminal:
   - `soak.sh night --from 23:00 --to 07:00`: a sleep every 20 minutes, one of them 30 minutes long. sudo asks once, to schedule every wake.
   - `soak.sh displaysleep`: ten display sleeps, each woken 30 seconds later.
   - `soak.sh lock`: eight lock screens, then `soak.sh lock --person` twice, locking with ctrl-cmd-Q. Lock Screen settings must ask for the password immediately. With that on, `displaysleep`'s wakes also land on the lock screen; unlock once it is done.
6. The person's rows, each marked just before it is done (the script says which length is next):
   - 20 lid cycles, closed 10 seconds and 2 minutes by turns: `soak.sh mark lid` before each close.
   - Fast user switching once, 5 minutes in a second account: `soak.sh mark fus`.
   - Each recovery drill, once, both displays live: `soak.sh mark drill <which>` just before it (`soak.sh mark drill "killall the extension"`). A drill's episodes are listed apart in the report and judged by its row in M8's "Recovery drills", not by the soak's zero unrecovered.
   - The hot-plug loop, once, both displays live: `soak.sh mark replug` before each of the 20 cable pulls. For the mode row, `swift Tools/soak/display-mode.swift list` gives the external's ID, then `set <ID> 1280 1024` and `set <ID> 1920 1080`, five times. The loop's other rows, and anything else worth a line: `soak.sh mark note <what>`.
7. `soak.sh status` at any time. After two hours, `soak.sh stop` writes the end row, exports the last of the log and writes the report.

## The energy suite

One display, on mains, the desktop visible, hands off. The covered phase drives TextEdit through System Events, so the terminal needs Accessibility (Privacy & Security).

- `Tools/soak/energy.sh video <the 4K60 clip's name or UUID>`
- `Tools/soak/energy.sh scene <a scene's name or UUID> --watts`: sudo asks once, for `powermetrics`, whose GPU power the scene's return is judged by; without `--watts` that line is not measured
- `Tools/soak/energy.sh idle`, which asks you to close Livepaper's windows, then to cover every display

`livepaper status` lists the library's names and UUIDs. `LIVEPAPER=<path>` picks the tool when no Livepaper is running. Stopped part-way, with ctrl-C or otherwise, the script still stops its `top` and `powermetrics`, closes its TextEdit document unsaved (quitting TextEdit only if it opened it), and wakes the display if it stopped with it asleep.

## Where the output goes

- A soak: `~/Library/Logs/Livepaper soak/<YYYY-MM-DD-HHMM>/`, holding `events.csv`, `samples.csv` and `log.txt`. The report goes to `docs/reports/soak-<date>.md`, which is committed and which the next soak compares against. The raw `log.txt` goes on the `pr-media` branch with `Tools/pr-media/publish.sh`, never into master.
- The suite: `~/Library/Logs/Livepaper energy/<YYYY-MM-DD-HHMM>/`, holding `energy.csv`, `watts.csv` with `--watts`, `link.csv` for a scene (when its display link stopped, from the extension's log), and `report.md`, the reading it prints at the end.
