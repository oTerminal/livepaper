# M1: engine spike

Answer the questions the rest of the roadmap depends on, with throwaway code, before any product code is written. See `docs/roadmap.md` for context.

## Rules

- All code goes in `Spikes/`, with its own `project.yml`. The product never imports it, and it is held to no quality bar beyond being readable enough to learn from.
- Every row below ends in a written result: what was run, what was observed, with `log stream` excerpts for `WallpaperAgent`, `pkd` and `amfid` where relevant. Results go into the four decision records.
- S0 runs first. If its second-Mac rows fail, stop and apply gate G1 before doing S6 to S8.
- Private API is studied from Phosphene (MIT, https://github.com/kageroumado/phosphene); anything adapted keeps its attribution. GPL projects are not read.
- Signing: the extension is signed separately, with an entitlements file containing `com.apple.security.app-sandbox`, before the app is signed. Never `codesign --deep`. No App Groups. No hardened runtime unless a row is testing it.

## Rows

| # | Question | Pass when |
|---|---|---|
| S0 | Does a wallpaper extension load without Apple signing? A minimal extension drawing a solid colour, registered at `com.apple.wallpaper`. Variants: ad-hoc and self-signed certificate; run from DerivedData and from /Applications; hardened runtime on and off; after a reboot; after a rebuild | "Livepaper" appears in System Settings > Wallpaper and the colour shows on the desktop and the lock screen, for each variant |
| S0b | Same build, zipped into a DMG, downloaded on a second Mac (checklist below) | The colour shows after Open Anyway alone. Record separately whether `xattr -dr com.apple.quarantine` was needed |
| S0c | Does a self-signed certificate keep the app's identity stable? Build twice with a source change | `codesign -d -r-` shows the same designated requirement for both builds; a login item registered by build 1 still launches build 2 without a duplicate entry in System Settings > Login Items |
| S1 | Where can the library live? (a) `~/Library/Application Support/Livepaper/` with a read-only home-relative sandbox exception on the extension; (b) the extension's own container, written by the app | The extension reads a video from the location with no consent prompt, across a rebuild. Darwin notifications arrive in both directions |
| S2 | Gapless loop with `AVSampleBufferDisplayLayer` and two `AVAssetReader`s, first in a plain window, then inside the extension | 200 consecutive loops of a 5 s clip with no gap between presented frames longer than 1.5 frame durations. Record CPU and energy against `AVPlayerLooper` on the same clip |
| S3 | Displays and Spaces: two displays, several Spaces, a fullscreen app, Stage Manager, unplug and replug, two identical monitors, a resolution change | Each display keeps its own video throughout; the display UUID is stable across replug |
| S4 | Sleep and lock: 20 lid cycles, one sleep over 30 minutes, lock screen, fast user switching, login before the app starts | Playback is advancing within 2 s of every wake; the lock screen plays video |
| S5 | Crossfade between two videos using two layers created up front | No flash, no frame where neither video is visible |
| S6 | Lock-screen transitions | No grey frame when locking or unlocking |
| S7 | 50 wallpaper switches in 10 s; then kill `WallpaperAgent` | Ends on the last video requested; recovers from the kill without a restart loop |
| S8 | Can the app select the Livepaper wallpaper programmatically, and restore the previous wallpaper when live wallpaper stops? Try a previous still image, a dynamic wallpaper and an Aerial | Record exactly what can and cannot be done with public API |

## Second-Mac checklist (S0b)

The second Mac must never have seen the project or its signing certificate.

1. Confirm macOS 26 or 27 and Apple Silicon. Note the exact version.
2. Download the DMG with Safari from the GitHub release (not AirDrop or a USB stick, which skip quarantine).
3. Drag the app to /Applications and open it. Expect the "Apple could not verify" dialog.
4. System Settings > Privacy & Security > Open Anyway; authenticate; open again.
5. System Settings > Wallpaper: is there a Livepaper entry? Select it. Does the colour show? Lock the screen: does it show there?
6. If step 5 fails: run `pluginkit -m -v -p com.apple.wallpaper` and save the output, then `xattr -dr com.apple.quarantine /Applications/Livepaper.app`, `killall WallpaperAgent`, reopen the app and repeat step 5.
7. Reboot and repeat step 5.
8. Send back: macOS version, the answer at steps 5, 6 and 7, and the `pluginkit` output.

## Gate G1

If S0b fails even after step 6, the desktop-window render host becomes the main path, the extension target is left out of release builds, and the lock screen shows a matching still. Record this in decision record 0001.

## Deliverables

- `docs/adr/0001` to `0004`, as listed in `docs/adr/README.md`.
- An energy budget for 4K60 playback, used as the M8 threshold.
- Specs for M2, M3 and M4 in this folder, written once the records above settle their inputs.

## Out of scope

Anything a user would see, error handling beyond what a row needs, tests.
