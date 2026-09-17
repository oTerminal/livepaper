# Run sheet: the rows that need a person

Everything that could be run without eyes, a second Mac, a second display or a lid has been run; see
`results/`. This is the rest. Each step says what to write down, and where.

Setup, once (already done on the development Mac):

```sh
cd Spikes
scripts/make-clips.sh && scripts/make-cert.sh && scripts/build.sh
scripts/install.sh applications selfsigned plain S1
cp clips/*.mp4 clips/*.mov ~/Library/Application\ Support/LivepaperSpike/
```

Every command below is run from `Spikes/`. `scripts/lp <command>` runs the installed app's command line
(`scripts/lp config mode=colour`, `scripts/lp check`, …).

The development Mac is back on its Aerial. To run these rows, launch the app and choose "Livepaper" in
System Settings > Wallpaper (`scripts/find-livepaper-in-settings.sh` opens the pane and confirms the entry
is there). A copy of the wallpaper store from before the spike is in `.context/backup/`. Keep a terminal running
`scripts/logs.sh | tee results/raw/<row>.log` during every row.

## S0: look at it (2 minutes)

1. `scripts/lp config mode=colour`. Is the desktop a flat blue (#0A85E3)? Lock the screen (ctrl-cmd-Q): is the lock
   screen the same blue?
2. Reboot. Log in, do not launch the app. Is the desktop still blue? The lock screen?
3. Write yes/no for each into `results/S0.md` under "What was observed".

## S0b: second Mac (the gate)

1. `scripts/package-dmg.sh` writes `build/Livepaper-spike-<version>-selfsigned-plain-S1.dmg`.
2. Put it where Safari on the second Mac can download it. A release on the private repo works if that Mac
   is signed in to GitHub:
   `gh release create m1-spike-s0b build/Livepaper-spike-*.dmg --prerelease --title "M1 spike S0b" --notes "Throwaway build for the second-Mac test."`
3. Follow the checklist in `docs/specs/M1-engine-spike.md` (steps 1 to 8) on the second Mac.
   One trap, so that a working setup is not recorded as a failure: after an install, the first extension
   instance gets killed once by the next launch of the app, and WallpaperAgent does not restart it
   (`results/S0.md`, "Hazard"). Step 6's "reopen the app" is such a launch. So whenever the colour is
   missing, run `killall WallpaperAgent` once more *without* relaunching the app afterwards, wait ten
   seconds, and look again before writing "fails".
4. Record in `results/S0b.md`: macOS version, the answers at steps 5, 6 and 7, whether `xattr -dr` was
   needed, the `pluginkit` output. Then set the status of `docs/adr/0001` and apply gate G1 if it failed.
5. If it fails, also try `scripts/package-dmg.sh adhoc plain S0` to tell a signing problem from an
   entitlement problem.

## S0c: login item across an update (5 minutes)

The API half is done (`results/S0c.md`). The half that needs a logout:

1. `scripts/install.sh applications selfsigned plain S1`, then `scripts/lp login register`.
2. Edit any string in `App/main.swift`, `scripts/build.sh`, `scripts/install.sh applications selfsigned plain S1`.
3. Log out and in. Did Livepaper launch (the status window shows its build number)? Is there exactly one
   Livepaper row in System Settings > General > Login Items?
4. Repeat with `adhoc` in place of `selfsigned`. Then `scripts/lp login unregister`.

## S3: displays and Spaces (needs a second display; two identical ones for the last part)

1. `scripts/lp config mode=video video=a-1080p30-h264.mp4`. Plug in the second display. In the log, each display
   gets its own `ACQUIRE new surface … display <id> <uuid>` line. Note both UUIDs.
2. Give the second display the other clip: `scripts/lp config mode=video video=a-1080p30-h264.mp4 display=<uuid>=b-1080p30-h264.mp4`
   (B is the hue-shifted one). Does each display keep its own video?
3. Walk through: add two Spaces and switch between them; make an app fullscreen and leave it; turn Stage
   Manager on and off; unplug and replug; change the resolution in System Settings > Displays.
   After each: does each display still show its own clip? Any black, grey or frozen surface?
4. After the replug: is the UUID in the new `ACQUIRE` line the same as before?
5. With two identical monitors: do they get different UUIDs? Swap their cables: does the video follow the
   monitor or the port?

## S4: sleep and lock (mostly waiting)

With a video playing. After every wake the extension logs
`s4: after <event>: desktop|preview surface … showed N new pictures in 2 s: PASS|FAIL`. Only a surface that
is on screen counts: the Settings preview, or a Space that is not showing, is throttled by the window
server and will say FAIL.

1. Close and open the lid 20 times, a few seconds apart. Count PASS lines: `grep -c "s4:.*PASS" results/raw/s4.log`.
2. Sleep for more than 30 minutes, wake.
3. Lock the screen: is the video playing on the lock screen?
4. Fast user switching to another account and back.
5. Log out, log in, do not start the app: is the video playing?

## S5: crossfade in the extension (the window half is done)

`scripts/lp config mode=video video=b-1080p30-h264.mp4 crossfade=1`, then back to `a-…` with `crossfade=1`, a few
times. Watch for a flash, or any frame where the blue shows through.

## S6: lock transitions

With a video playing, lock and unlock ten times (ctrl-cmd-Q, then Touch ID). Any grey frame going in or
coming out? The log shows whether the agent asked for a snapshot and got the current video frame
(`SNAPSHOT requested … -> current video frame`).

## S7 and S8

Automated parts are in `results/S7.md` and `results/S8.md`. The part that needs eyes: during
`scripts/lp s7 a=a-1080p30-h264.mp4 b=b-1080p30-h264.mp4`, does the desktop end on B (the hue-shifted clip) with
no black or grey on the way?

## When done

`scripts/cleanup.sh`, then pick your old wallpaper in System Settings > Wallpaper.
