# M8: hardening

Run the finished product for a day and a night, hurt it on purpose, measure what it costs, fix what that finds. No lane of its own: it starts where the three lanes join, so there is a popover, a rotation driver and a login item to soak (M5-engine.md, M6-screens.md, M7-system-integration.md). See `docs/roadmap.md`, records 0001 to 0003, and `Spikes/results/S2.md` for the thresholds.

## Rules

- No new features, no design changes. A component fix takes M3-design-system.md's loop and a `DECISIONS.md` entry; a Core fix is test-first (M2-core.md); what would change a record is raised, not made.
- A number is a threshold from this file or `S2.md`, or first measured here. The second kind (watts, memory, late frames, fast user switching) is a baseline for the next soak, not a criterion.
- Tooling is product code under `Tools/soak/`, its pure logic a new `LivepaperSoak` target in `LivepaperKit`: nonisolated, Foundation only, shipped with nothing. Nothing in `Spikes/` is run or imported; what is repeated is rewritten.
- The soak does not run in CI. CI runs `make gen build test lint` on macos-26 / Xcode 26 over `LivepaperSoak`'s tables and its log fixture; the rest runs on the development Mac, by script where one can and by a person where none can. Captures show a window, not the display, and are looked at before publishing (CLAUDE.md). Vocabulary is `CONTEXT.md`'s.

## What earlier milestones settled

| Fact this milestone tests against | Source |
|---|---|
| Healthy is half the expected pictures or more, else the ladder `.flush`, `.rebuildSurface`, `.rebuildPipeline`, `.restartAgent` by attempt; only a surface on screen is judged; no agent restart twice in 600 s; `HeartbeatTiming.standard` is 20 s grace, 15 s lifetime, 10 s step | `Watchdog.swift` |
| Covered gives `.pause`, decoder kept; asleep, Low Power Mode and battery with its rule on give `.suspend`, decoder released; conditions over 30 s old are ignored | `PlaybackPolicy.swift` |
| A covered surface shows no new pictures and is never a stall; a replug is a new surface ID for the same display UUID; a mode change is stretched | `S3.md`, M5-engine.md |
| Replacing the bundle kills the extension once and the agent does not restart it; `killall WallpaperAgent` does. The spiral detector has never fired. A restart redraws every desktop | `S0.md`, `S7.md`, `S8.md` |
| A scene (M11) is drawn by the extension with Metal at 30 fps. Its watchdog count is the pictures its GPU finished; a display link the system stops calling while the engine answers is `withheld`, read as `notComposited`, never a stall. Its cost is GPU time, which `top`'s power score does not see. Cover, sleep, wake and the lock screen were not run with a scene | M11-wallpaper-engine-scenes.md, "As built"; `S10.md` |
| 4K60, one display, desktop visible: extension at or under 4 % CPU and `top` power 5; `VTDecoderXPCService` summed 5 % and 5; WindowServer at most 25 over its paused score that session; all three back at paused levels within 5 s of covering or display sleep. One run, machine in use. At 60 fps a frame is sometimes one refresh late mid-pass, never at a seam | `S2.md`, `energy-suite.sh` |

## The soak

24 hours on the development Mac from a stable install, no bundle replaced since the last agent restart; the clock starts at the first `.live`. Six wallpapers go in through the product importer: two bundled CC0 samples, a 1080p60 and a 4K60 HEVC clip from `Tools/soak/clips.sh` (frame counter burned in, as `make-clips.sh` did), one of the person's own with audio, and one scene imported from the person's Workshop items (M11-wallpaper-engine-scenes.md). The built-in display rotates all six, shuffled, every 5 minutes and on wake; the external holds the 4K60 clip. `Tools/soak/soak.sh` keeps "Log playback metrics" on (M5-engine.md, kept past M6-screens.md) and samples CPU and RSS every 5 minutes: 288 samples.

A lid cannot be closed by a script, and `pmset schedule` and `pmset relative` need root (`pmset: This operation must be run as root`), so the sleep rows take one `sudo`.

| Event | Driven by | Stands in for |
|---|---|---|
| Sleep every 20 minutes overnight: `sudo pmset relative wake 120`, then `pmset sleepnow`; once scheduled 30 minutes out | Script | The wake path and S4's long sleep. `relative wake` cannot be cancelled and is imprecise (`man pmset`), so times come from the log. Not the lid: no clamshell, no display leaving |
| 20 lid cycles, 10 s and 2 minutes closed by turns (`S4.md` left them here; one cycle played "instantly") | Person | Nothing else can. With the external attached the Mac may stay awake on it alone while the built-in display leaves; the report counts both kinds apart |
| `pmset displaysleepnow`, woken by a key, ten times | Script | A display asleep: `.suspend` and the decoder's release |
| `open -a ScreenSaverEngine`, password required immediately, ten times, back with `caffeinate -u -t 5` | Script | The locked surface, nobody at the keyboard; a person does two of the ten with ctrl-cmd-Q |
| Fast user switching once: a second account, 5 minutes, back | Person | Nothing else can: accessibility is ruled out, and whether `CGSession -suspend` still exists on macOS 27 is checked here, not assumed. Recorded, not passed |

A **stall** is a watchdog check on a surface on screen and not covered whose verdict is `.recover(_)`, or the host's status leaving `.live` for `.recovering(_)`. An **episode** opens there and closes at the next `.healthy` for that surface, or `.live` for the host. It is **unrecovered** when it never closes, is open at the end, or reaches `.restartAgent`: a restart redraws every desktop, is allowed once per 600 s, and cures the install hazard, not a wake. Recovered episodes pass, each listed with its trigger and level; a pattern is a defect fixed here.

`Tools/soak/soak-report` reads `log show` output and the CSV and prints, per trigger (wake, lid, display wake, unlock, replug, rotation), the events and episodes by level and outcome, the largest presented gap per wallpaper and whether at a seam, RSS by hour, and every episode's excerpt. It goes to `docs/reports/soak-<date>.md`, which the next soak compares against. The raw log goes on `pr-media`, not into master.

## Hot-plug loop

Once during the soak, both displays live, a person on the cable.

| Step | Count | Pass when |
|---|---|---|
| Cable out, 5 s and 30 s by turns | 20 | Each replug acquires the same UUID, on that display's wallpaper within 2 s; `.healthy` at attempt 0 on both; the popover lists it again |
| `pmset displaysleepnow`, wake by key | 5 | `.healthy` at attempt 0 on both |
| 1920x1080 to 1280x1024 and back, `Tools/soak/display-mode.swift` | 5 | Right proportions after each, by capture; no stall |
| Stage Manager off and on; a second Space, there and back | 3, 5 | No surface event; each display keeps its wallpaper; no grey frame |
| A fullscreen app on each display in turn | 5 | The covered display is `.pause(.desktopCovered)` and never judged, the other untouched, advancing 2 s after leaving it |

## Energy, idle and memory

`Tools/soak/energy.sh` repeats S2's suite on product code: one display, mains, System Settings closed, `caffeinate -dis`, six 5 s `top` samples after a 15 s warm-up. `powermetrics` gives watts but "must be invoked as the superuser", so it is optional and the budget is held to top's score either way.

| Measurement | Pass when |
|---|---|
| The 4K60 clip, one display, desktop visible, machine idle | Inside the S2 budget, line for line |
| Then a fullscreen app over it, then `pmset displaysleepnow` | All three back at paused levels within 5 s; decoder kept when covered, `VTDecoderXPCService` gone when the display sleeps |
| A scene on one display, desktop visible, then covered, then `pmset displaysleepnow` | First measured here, as M11 left it: `top` and, with `sudo`, `powermetrics`' GPU power, recorded as a baseline; the link stopped and the GPU back at paused levels within 5 s of covering or sleep |
| Idle 5 minutes each (60 samples): the app with popover and window closed, then the extension with every display covered | The roadmap's "about 0 %" read as a mean at or under 0.1 % CPU, no sample above 1 % |
| Memory over the soak | Hour 24's mean RSS at most 10 % over hour 2's, app and extension; hour 1 is warm-up; under 200 samples, inconclusive |

Two questions are then measured and either fixed or accepted in writing. The 60 fps late frame: 200 loops of the 4K60 clip on the desktop surface with the probe on, machine idle, plus the soak's metrics lines. No mid-pass gap over 1.5 frame durations means load, accepted, recorded with its count; any gap is the engine's, fixed here. The audio seam click, only if M5-engine.md's Audio row recorded one: 20 seams at volume 0.5. Heard, it is fixed in the importer's audio trim (M4-import.md) or the engine's audio timeline, with a before-and-after pair; not heard, closed in the report.

## Recovery drills

Each once during the soak, both displays live. "Seen in" is where the user sees it; each keeps its log excerpt.

| Drill | Expected | Seen in |
|---|---|---|
| `killall WallpaperAgent` | Back within 2 s, one acquire per surface, right wallpapers, no spiral. launchd may spawn the agent twice (`docs/research/wallper.md`); that is not a failure | One redraw |
| `killall` the extension | The ladder climbs; live inside lifetime plus three steps plus the restart | `StatusLine`, then clear |
| Replace the bundle, launch twice | Live inside grace plus one step; assignments and playlist intact | `StatusLine` |
| Truncate `render-state.json`, then garbage | It keeps what it shows; the app's next apply heals it | Nothing |
| Delete a playing wallpaper's folder | Its poster, else the neutral colour; the app says the files are missing | The card's status |
| Disk full mid-import (`mkfile`); a source cut in half | Both fail with a reason; `.staging/` empty; `library.json` unchanged | `ImportProgressRow` |
| Library folder moved away, launch, back, launch | Empty library, no crash; the library comes back intact | `EmptyState` |
| Cut `library.json` short; `kill -9` during a commit | `library.previous.json` loads (`LibraryStore.swift`); no orphan folder, no entry without files (M4-import.md) | Nothing |
| A display UUID never seen: a monitor never attached here, else an unconnected UUID in `render-state.json` | "Apply to all" or the neutral colour, listed, no verdict on it; without a monitor, carried to M10-1.0.md | Popover |

## Accessibility pass

Against the real system settings, not the Gallery's switches, since some effects honour only the real one (`DECISIONS.md`). Over every M6-screens.md screen and the popover: VoiceOver on each control, the app by keyboard alone, then Reduce Motion, Reduce Transparency and Increase Contrast, in light and dark, judged by M3-design-system.md's rules. Recorded as a table per screen in the PR: element, what VoiceOver said, keyboard reach and order, what each setting changed, a crop per appearance; transcripts stay out of the repo. A component fault goes through M3's loop, a screen fault into the screen.

## Bug bash

One row per bug the roadmap's Context reports in Wallper and per row of its Risks table; where the proof is not M8's, the row says whose.

| Bug or risk | Proved by |
|---|---|
| Playback not resuming after sleep; the watchdog | The soak, zero unrecovered episodes |
| The black flash at the loop seam | The largest gap per wallpaper; the 200-loop row (the file itself by M4-import.md) |
| Menu-bar tint mismatch | Not ours in extension mode (roadmap): a menu-bar capture per wallpaper, light and dark |
| The library emptying on restart | The manifest, mid-commit and missing-folder drills |
| WallpaperAgent wedging | The kill drill; 50 switches in 10 s (M5-engine.md's S7 row); the spiral count |
| Display hot-plug | The loop |
| Energy | The suite and the idle rows |
| ffmpeg on untrusted files | The disk-full and cut-source drills |
| The extension orphaned by an update | The replace-the-bundle drill |
| Identity per build, Sparkle, translocation, the downloaded build | M9-release-engineering.md, on the second Mac |
| The private API moved; the store's format | M10-1.0.md's checklist; the self-check's line is read once in the soak |
| Restoring an Aerial | Record 0003 and M7-system-integration.md's leaving flow |

What this finds is fixed here and listed under "As found" in the PR: what found it, the cause, the fix, a before-and-after pair, a re-run of the drill, and the 200-loop row if the engine was touched. A fix must not add a feature or a pause rule, change a record or a schema version, put private API outside `WallpaperAgentBridge`, add a poll that runs while nothing changes, or raise a threshold to meet it: a wrong threshold is re-measured and the report says so.

## Seams for test-first work

Swift Testing table tests in `LivepaperSoak`, no display and no clock of their own, over a checked-in fixture of real lines from the first soak: the extension's surface events, wallpaper per generation, verdicts, ladder and metrics line (M5-engine.md).

| Seam | Tested as |
|---|---|
| Log line parser | Each line to an event, its text pinned by a row against M5-engine.md's "As built", so a rename there fails a test instead of counting zero; other subsystems ignored; an unparsed line is counted, never dropped |
| Episodes into stall counts | Reducer over events and time, by the definitions above: recovered at a level, or unrecovered three ways; surfaces counted apart; each episode charged to the trigger before it |
| Budget comparison | `EnergyBudget` (S2's numbers) against a measurement, line by line; WindowServer's delta from that session's paused baseline; watts present or absent; the 5 s return |
| Report | Episodes, samples and metrics into the sections above; hourly RSS means and the 10 % rule; gaps over 1.5 frame durations split at-seam and mid-pass; an empty log reports no soak, not a pass |

## Done when

- The soak report is committed under `docs/reports/` with zero unrecovered episodes; the loop, the suite, the two questions and every drill have a row in the PR with evidence.
- The idle, memory and 4K60 numbers meet the tables above; the watts are in the report, or it says why there are none.
- One accessibility table per screen is in the PR, nothing left open, and the PR shows a screenshot of every state the drills name and of each appearance the pass covers, a wake recovering and a lid cycle as a GIF with the MP4 beside it, and a before-and-after pair per fix (CLAUDE.md).
- `LivepaperSoak`'s tables pass with `swift test --package-path Packages/LivepaperKit`, and `make gen build test lint` is green locally and in CI.

## Out of scope

Signing, the DMG, Sparkle, the move-to-Applications prompt and the second Mac (M9-release-engineering.md). The beta-seed checklist and a never-seen display if none can be borrowed (M10-1.0.md). Two identical monitors (dropped, `Spikes/RUNSHEET.md`). New pause rules, thermal state, any feature.
