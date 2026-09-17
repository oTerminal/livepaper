# M1 engine spike

Throwaway code that answers the questions in `docs/specs/M1-engine-spike.md`. The product never imports
anything from here, the root `project.yml` does not know this folder exists, and SwiftLint skips it.
It is Swift 5 mode with hand-rolled threading (the extension's state lives on the main thread, each `LoopEngine` on its own serial queue, the probe on a third), and has no tests, on purpose.

Results are in `results/` (one file per row, raw logs in `results/raw/`) and the decisions they led to
are in `docs/adr/0001` to `0004`. What still needs a person is in `RUNSHEET.md`.

Parts are adapted from Phosphene (MIT). `NOTICE` lists which, and carries its licence. No GPL project was read.

## Layout

| Path | What |
|---|---|
| `project.yml` | XcodeGen project: `Livepaper.app` (`app.livepaper.spike`) embedding `LivepaperExtension.appex` (`app.livepaper.spike.extension`, extension point `com.apple.wallpaper`). Xcode does not sign. |
| `Extension/` | The wallpaper extension. `PrivateBridge.swift` is all the private API; `XPCHandler.swift` the agent-facing protocol; `SurfaceStore.swift` one CAContext per surface. |
| `Shared/LoopEngine.swift` | S2: the gapless loop, its metrics, and the displayed-frame probe. |
| `Shared/SurfaceLayers.swift` | The layer tree of one surface: colour + two video layers made up front (S5, S7). |
| `App/main.swift` | The host app. Every row the app can drive is a command (listed at the top of the file). |
| `scripts/` | Build, sign, install, package, log and measure. |

## Running it

```sh
cd Spikes
scripts/make-clips.sh                 # test clips (ffmpeg), not committed
scripts/make-cert.sh                  # self-signed identity in its own keychain
scripts/build.sh                      # unsigned app, fresh CFBundleVersion each time
scripts/install.sh applications selfsigned plain S1    # sign inside-out, register, launch
scripts/logs.sh                       # WallpaperAgent / pkd / amfid / spike lines, live
```

Then choose "Livepaper" once in System Settings > Wallpaper. After that:

```sh
cp clips/*.mp4 clips/*.mov ~/Library/Application\ Support/LivepaperSpike/
scripts/lp config mode=video video=a-1080p30-h264.mp4            # play in the extension
scripts/lp config mode=video video=b-1080p30-h264.mp4 crossfade=1
scripts/lp config mode=colour
scripts/lp s2 engine=sbdl clip=$PWD/clips/a-1080p30-h264.mp4 loops=200 probe=2 out=/tmp/s2.json
scripts/missing-frames.py < /tmp/s2.json
```

`scripts/cleanup.sh` removes everything the spike installed (app, registration, keychain, library folder).

Two traps when driving it from a terminal:

- In zsh `log` is a builtin. Use `/usr/bin/log`, or the scripts (they run under bash).
- A binary started from a terminal inherits the terminal's TCC identity. Anything about consent
  (S1 b) has to be launched with `open -n -a /Applications/Livepaper.app --args …`.
