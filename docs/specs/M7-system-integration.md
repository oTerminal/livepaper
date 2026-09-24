# M7: system integration

Wire the app to macOS and to the doors that are not the window: the login item, hotkeys, Services and Open With, the `livepaper://` scheme, the `livepaper` tool, Dock and menu-bar drops, rotation, onboarding (which makes Livepaper the system wallpaper), leaving and diagnostics. It continues lane A after M5-engine.md and wires what lane B's M6-screens.md draws. See `docs/roadmap.md` (Import, Rotation, System integration, Selection, Quit, First run) and records 0001 to 0004, 0003 above all.

## Rules

- Code goes in `LivepaperSystem` (MainActor: login item, hotkeys, the store, rotation, the socket, diagnostics), `LivepaperCore` (the pure `Command` grammar), `App/`, `CLI/` and `Resources/Samples/`.
- No permission-gated API (`docs/roadmap.md`): no Accessibility, Screen Recording, Automation or Full Disk Access. Hotkeys are Carbon, System Settings is opened by URL and never driven, the store is a file in the user's Library. Wallper's Apple event to Settings costs a TCC prompt (`docs/research/wallper.md`).
- The app is the only writer of the manifest, `render-state.json` and the store (record 0002). Every door becomes a `Command` the app model runs; nothing else, the CLI included, writes a file.
- One type touches the store, at selecting and leaving only (record 0003): never on a launch, never on Quit, nothing when Livepaper is already selected, never a whole-file swap.
- The login item is `SMAppService.mainApp`: no LaunchAgent plist, no helper, the row showing real status and never intent. A hotkey never animates the interface (M3-design-system.md); the crossfade is content and still runs.
- Vocabulary is `CONTEXT.md`'s; "Selection" is Livepaper being the system wallpaper, what a display shows an **assignment**. Test-first at the seams below with an injected clock, a seeded RNG and fakes. CI is macos-26 / Xcode 26.

## What earlier milestones settled

- **Nothing public selects an extension's wallpaper or tells that one is; editing the store does** (`Spikes/results/S8.md`, S8b; `Spikes/App/WallpaperStore.swift`): Desktop entries rewritten to the extension's provider with the `livepaper` configuration, Idle entries left, a copy kept first, one `killall`, `ACQUIRE` 0.27 s later, every desktop redrawn once. Write only after `pluginkit -m -i` lists the extension; the fallback is the Wallpaper pane and a click.
- **The heartbeat's `desktopSurfaceAcquired` flag tells the app it worked** (`Heartbeat.swift`, M2-core.md), read as `RenderHostStatus.live` against `.notSelected`. M5-engine.md fixes the bundle identifier and the choice identifier `livepaper`; M7 writes them.
- **The login item follows the bundle** (`Spikes/results/S0c.md`): `SMAppService.mainApp` read `enabled` after a second build replaced the first, and launched it after a logout; its four statuses are one per `LoginItemRow` state. Wallper syncs from real status every launch and never reached requires-approval (`docs/research/wallper.md`).
- **`nextRotation`** (`Rotation.swift`, M2-core.md): a `.tick` waits out the interval since `lastRotation`, `.wake` and `.login` always rotate, deleted wallpapers are skipped, a seeded RNG fixes the order. `RotationState` is not `Codable` today; M6-screens.md adds that, and persists a `RotationState` per display in `app-state.json`.
- **The install hazard** (`Spikes/results/S0.md`): after an install or update the next launch kills the first extension instance once and the agent does not restart it. M5-engine.md's ladder cures that, so onboarding plays no part in it.
- **`SystemServices`** (`M6-screens.md`). The Settings login, hotkey and leave rows talk to a `SystemServices` protocol declared in `LivepaperCore`, answered on fakes by `FakeSystemServices`. `LoginItem`, `Hotkeys` and `Selection` below are the real answer to it, assembled in `App/`; the protocol's shape is M6's and is not changed here.
- **Hand-offs.** M2-core.md left the sensors to "M5 and M7": M5-engine.md took displays, power, lock, sleep and occlusion, M7 takes hotkeys and the login item. M4-import.md left Services and the URL scheme here, the Open panel to M6-screens.md. Playlists, assignments and mute are M6-screens.md's; `livepaper-cli`'s comment promising the URL scheme is rewritten here.

## Parts

| Part | Module | Does |
|---|---|---|
| `WallpaperStore` | `LivepaperSystem` | The spike's edit productionised: `selecting`, `deselecting`, the kept copy at `LibraryLocation.keptWallpaperStore` (added to Core). Every read checks the shape it expects and throws |
| `Selection` | `LivepaperSystem` | Select or leave: pluginkit, edit, one `killall` and not a burst (`docs/research/wallper.md`), 30 s for `.live` (over `HeartbeatTiming.standard.grace`), else the pane. Nothing written when already `.live` |
| `LoginItem` | `LivepaperSystem` | `SMAppService.mainApp` behind `LoginItemState`, the pane through `openSystemSettingsLoginItems()`, `reconcileLoginItem(intent:status:bundle:)` at every launch: the bundle path and requirement kept with the intent tell an identity that moved, which registers again, from the user turning it off. The intent, the bundle path and the requirement go into `AppState` at 1.1 (M6-screens.md). `register()` and `status` are synchronous, so the row answers in the same turn; nothing registers while translocated |
| `Hotkeys` | `LivepaperSystem` | Carbon `RegisterEventHotKey` for four unassigned actions: pause or resume all, next wallpaper, mute or unmute, open the library, persisted in `AppState` at 1.1 (M6-screens.md). `eventHotKeyExistsErr` reaches the recorder's `conflict` closure, which names another Livepaper action and says nothing macOS did not |
| `RotationDriver` | `LivepaperSystem` | The `rotation` of M6-screens.md's `AppState` (`app-state.json`, schema-versioned, app-written, atomic) loaded at launch, no second file, one timer for the earliest `lastRotation + interval` among displays with a playlist, so a relaunch continues the pass. `.wake` from M5-engine.md's sleep sensor, `.login` once a session. A paused display gets no ticks and counts from the resume; `next` works there and leaves it paused; pause rules do not hold rotation. Results reach displays as assignments |
| Entry points | `App/` | `CFBundleURLTypes`; `NSServices` "Set as Live Wallpaper" with `NSSendFileTypes` and `public.folder`; `CFBundleDocumentTypes` at `LSHandlerRank` `Alternate`, never a video file's default app; `application(_:open:)` for Open With and the Dock; the menu-bar button taking `.fileURL` drops. All need an `info:` block in `project.yml` |
| `Command` | `LivepaperCore` | The grammar below, shared by the scheme, the socket and the tool: parse, render back, reject the rest with a reason |
| `CommandServer`, `livepaper` | `LivepaperSystem`, `CLI/` | A socket at `LibraryLocation.commandSocket` (`command.sock`, 0600): request line, JSON reply line, close. The tool turns arguments into a `Command`, opens the app when the socket is absent, exits with a code, and gains the `LivepaperCore` dependency it lacks |

## The grammar

`livepaper://<verb>?<key>=<value>`. The verb is the host. A path, fragment, port, user name, or a key the verb does not take, is a rejection.

| Verb | Keys | Does |
|---|---|---|
| `import` | `file` (absolute, may repeat), `set` (`all`) | Imports each through `discoverSources`; with `set=all` and one wallpaper resulting, new or duplicate, assigns it everywhere |
| `set` | `wallpaper` or `playlist` (a UUID in the library), `display` (a UUID or `all`) | Assigns. An ID the library does not hold is refused |
| `pause`, `resume`, `next` | `display` (default `all`) | The transport actions; `next` moves on a display with a playlist |
| `mute`, `unmute` | none | Global mute (its state is M6-screens.md's) |
| `library`, `settings` | none | Opens the library window, or Settings |
| `diagnostics` | none | Clipboard from the app, returned over the socket, printed by the CLI |
| `status` | none | Socket only: host status, displays and assignments, the library's IDs and names, pause and mute, as JSON |

Wallpapers are named by ID, never by path; `file` is read by the importer alone; no verb runs anything. An `import` arriving through LaunchServices is confirmed in the window first, any web page being able to open the scheme. Services and the menu-bar drop are `import` with `set=all`, neither naming a display; Open With and the Dock are `import` alone, and the app being `LSUIElement` the Dock is a door only while the window is open.

The CLI uses the socket, not the scheme: LaunchServices reports only that the app took a URL, so there is no reply and no exit code, and an XPC Mach service needs a launchd job the app lacks. With none there it opens the app by `NSWorkspace.urlForApplication(withBundleIdentifier:)` and retries; `set` also takes a name, resolved through `status`. M7 confirms and records three things: that the socket path fits `sockaddr_un`'s 104 bytes, else it moves to the temporary folder; whether `eventHotKeyExistsErr` covers a combination another process holds; and where a session's start comes from (`utmpx`, else `kern.boottime`).

## Onboarding and leaving

Onboarding runs on the first launch only, recorded in preferences with the version that ran it. Wallper's seven slides and 46 s to a live wallpaper are the bar to beat (`docs/research/wallper.md`).

| Step | Card | Does |
|---|---|---|
| 1 | "Add a wallpaper" | Drop a file on the card, pick a sample, or use the Open panel (M6-screens.md's); the import runs and its result goes to every display |
| 2 | "Open at login" | Primary registers the login item and shows real status; needs approval offers the Login Items pane; secondary skips |
| 3 | "Make Livepaper your wallpaper" | `Selection.select`, done on `.live`. On an unreadable store or no `.live` in 30 s the Wallpaper pane opens with the words to choose "Livepaper" |

| First launch | Does |
|---|---|
| Fresh | The three steps |
| Translocated (the path holds `/AppTranslocation/`) | Nothing registered or written: the card asks the user to move Livepaper to Applications. M9-release-engineering.md replaces it |
| After an update | No onboarding; the login item is reconciled; M5-engine.md's ladder brings the desktop back |
| The store already names Livepaper everywhere | Step 3 writes nothing and completes on the flag |

Leaving, from Settings: `Selection.leave` puts back from the kept copy, entry by entry, what each Desktop entry named before, an Aerial included, wherever Livepaper is still named, leaving alone entries changed since; one agent restart, then the copy goes, and with no usable copy the pane opens. The login item is unregistered, the library kept, the app quits, and with no surface acquired the system draws the previous wallpaper; a next launch shows step 3 only. A user who picked another wallpaper by hand gets `.notSelected` in the popover (M6-screens.md) with a button to the pane, and no edit.

Samples: three CC0 loops, 5 to 15 s, SDR, H.264 or HEVC in mp4 so they import by remux, under 10 MB each; `PROVENANCE.md` gives each one's title, author, source URL, licence, date fetched, SHA-256 and what was done to it. The roadmap puts samples in M9, but onboarding needs them, so M7 adds them and M9-release-engineering.md checks the notices ship.

## Diagnostics and the restart button

M6-screens.md leaves the diagnostics export here, so M7 adds its rows to Settings on M3-design-system.md's components: "Copy diagnostics" copies the report, "Save…" uses a Save panel, `livepaper diagnostics` prints it.

- **Holds**: the app's and extension's versions and builds; macOS and hardware; whether the bundle is translocated; the self-check line and `RenderHostStatus`; per display the UUID and assignment by ID; pause rules, pauses and mute; the login item's status and intent; the store's shape check (Desktop entries, how many name Livepaper, whether the kept copy exists); the extension's log lines.
- **Never**: a wallpaper's name, any path, the user's name, the Steam account's name (M12-workshop.md), the store's file lists, another process's log. Lines are redacted of home paths and importable file names, and telemetry stays none.
- **Log lines** come from `/usr/bin/log show` on the extension's subsystem, 10 minutes, 200 at most; `OSLogStore.local()` is understood to need an entitlement this app cannot have; M7 confirms that, and that a plain user gets lines at all. Wallper logs nothing, so its reports carry no evidence (`docs/research/wallper.md`).
- **"Restart wallpaper service"** (`StatusLine`, wired by M6-screens.md) calls `RenderHost.recover(.restartAgent)` through `allowAgentRestart`; the line shows `.working`, the result, or when it can next be tried.

## Seams for test-first work

| Seam | Tested as |
|---|---|
| `Command` | Table: every verb parses and renders back to the same URL; rejections for an unknown verb or key, a path, a fragment, a relative or empty `file`, an ID that is not a UUID. Each CLI command maps to the URL it sends, with usage errors and a name resolved against `status` |
| Store edit | Copies of real stores, personal paths replaced, in S8b's two shapes (24 Desktop entries across 11 Spaces; 2 entries): select rewrites every Desktop and no Idle entry; a store with none gets one at `SystemDefault`; a second select writes nothing; deselect gives back the original, dates included; an unreadable store throws |
| `Selection` | Reducer with a clock over pluginkit, the write, `.live` and timeout: selected, fallback to the pane, still waiting; already `.live` writes nothing; a leave with no copy falls back |
| `reconcileLoginItem` | Table: four statuses × intent on, off, none × same or changed bundle |
| Hotkeys | An assignment round-trips through its `AppState` 1.1 form; the conflict answer is free, another Livepaper action by name, or taken elsewhere |
| Rotation driver | Reducer with an injected clock and a seeded RNG: the timer re-arming from the loaded state, a tick at the interval, wake, login once a session, a pause dropping ticks and counting from the resume, `next` while paused, M6-screens.md's `app-state-v1.0.json` still loading beside the 1.1 fields |
| Entry-point routing, redaction | Pure: door and candidates to import alone or import and set, several results never setting; and the home path, a wallpaper's name, any library or source file name and `<private>` all gone from the report |

## Checks on screen

| # | Check | Pass when |
|---|---|---|
| Onboarding | Preferences and library removed, three steps, a sample chosen, nobody in System Settings; then again with the store unreadable | Live within 30 s of step 3, one store write and one restart logged, the kept copy there; unreadable, the pane opens and the click finishes it |
| Translocated, update | Opened from Downloads; then the bundle replaced and launched twice | The move message and nothing written; then no onboarding, the login item on (S0c), the desktop live after M5's ladder |
| Login | On, off, on; off in Login Items; run translocated | The row matches System Settings every time; needs approval opens the pane |
| Hotkeys | ⌃⌥P and ⌃⌥N with another app frontmost; then record ⌘Space | Both fire without animating the popover; the recorder's answer for ⌘Space matches what `RegisterEventHotKey` returned |
| Doors | Services on a .mov and a Wallpaper Engine folder; Open With on a .mp4; three files on the Dock icon; one on the menu-bar item; `livepaper://set?wallpaper=../x` | Set everywhere; imported, not set; imported, not set; imported and set; refused with a log line |
| CLI | `status`, `import <file> --set`, `next`, `pause`, `resume`, `mute`, `set <name>`, `diagnostics`, and one run with the app not running | The app launches, each answers, exit codes 0, 1 on refusal, 2 on usage, 3 when unreachable |
| Rotation | Three wallpapers on the shortest interval M6-screens.md's playlist row offers; relaunch mid-pass; a lid cycle; log out and in; paused past two intervals, then resumed | Rotates with the crossfade, continues the pass, rotates on wake and once at login but not on a relaunch, nothing while paused, the next an interval after |
| Leaving, diagnostics | An Aerial as the previous wallpaper, two Spaces; then copy the report and click Restart twice | The Aerial back on every Space in 5 s, Login Items empty, the library intact, the next launch at step 3; every section present with no user name, home path or wallpaper name; one restart, the second reporting the wait |

## Done when

- The seam tests pass with `swift test --package-path Packages/LivepaperKit`, and `make gen build test lint` is green with the CLI built.
- Every check passes, with its evidence in the PR (CLAUDE.md): onboarding, Services and a hotkey firing as video at 0.1x, MP4s linked; the login row's four states, the recorder in conflict and the CLI transcript as screenshots; a rotation crossfade off the desktop's wallpaper window as M5-engine.md found; leaving before and after.
- `Resources/Samples/PROVENANCE.md` names every sample's source and licence, and `CLI/main.swift`'s comment and `LivepaperSystem.swift`'s say what was built.
- An "As built" section, as M4-import.md has: the socket path, the three confirmations above, the login status macOS reports after the user turns the item off, what the store looked like here, and whether the `livepaper` tool ships inside the app bundle or beside it, which M9-release-engineering.md's signing order needs.

## As built

What M7 decided or found on the way, for M8-hardening.md, M9-release-engineering.md and M10-1.0.md. Names are quoted from the code.

### The doors, the socket, rotation, diagnostics and Restart

- **Info.plist.** `project.yml`'s `info:` block writes `App/Info.plist` (generated, ignored by git), which Xcode merges with the `INFOPLIST_KEY_` settings. It holds `CFBundleURLTypes` (`livepaper`); one `NSServices` entry, "Set as Live Wallpaper" (`NSMessage` `setAsLiveWallpaper`, `NSPortName` Livepaper, an empty `NSRequiredContext` so it is on without a visit to the Services list, `NSSendFileTypes` the types of `importableExtensions` and `public.folder`); and `CFBundleDocumentTypes`, a Movie entry (MPEG-4, M4V, QuickTime, WebM, Matroska, AVI, WMV) and a GIF Image entry, each Viewer at `LSHandlerRank` `Alternate`. The versions are `$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)`: XcodeGen's own defaults would win otherwise.
- **The `livepaper` tool ships inside the app**, at `Contents/Helpers/livepaper`: in `Contents/MacOS` it would collide with `Livepaper` on a case-insensitive disk. The app target depends on `livepaper-cli` and copies it in an Embed Dependencies phase with CodeSignOnCopy, so it is signed before the app is sealed; `codesign --verify --strict` passes on the app. The tool carries an Info.plist section (`CREATE_INFOPLIST_SECTION_IN_BINARY`), so its signature names it `app.livepaper.cli` rather than `livepaper-<hash>`. M9's signing order signs it as nested code before the app.
- **Doors** (`App/Shell/Doors.swift`). `application(_:open:)` takes files and links: files dropped on the Dock icon are told from Open With by the Apple event's sender (`com.apple.dock`), both an import alone. A link is parsed by `EntryPoint.urlScheme`; a rejection is logged (`door: livepaper:// link refused: …`) and goes no further; an import is asked about first in an alert on the library window, which opens for it (`ImportConfirmation`: the file's name, its path shortened to `~`, Import or Import and Set, and Cancel); `diagnostics` puts the report on the clipboard. The Services provider is `Doors` itself (`NSApp.servicesProvider`, `NSUpdateDynamicServices()` at launch). The menu-bar item's button is covered by a view registered for file URLs whose `hitTest(_:)` answers nil, so clicks reach the button and drops reach the view; the button highlights while files are over it. A command that arrives before the launch has read the library and the displays waits for it (`untilReady()`).
- **Commands** (`AppModel+Commands.swift`) run through the window's own actions and log `command: <what> from <door>`, then `done` or `refused: <reason>`, never a path. An import goes through the import list, so its rows show in the window, and the reply waits for them (`ImportWaiter`): one line per source (`Command.importReply`), and with `set=all` the one wallpaper that resulted is set on All Displays. A wallpaper, playlist or display that is not there is refused in `CommandRefusal`'s words; `next` with no display showing a playlist is refused; `pause` and `resume` without a display are Pause All and Resume All.
- **The socket** is opened at `LibraryLocation.commandSocket(fallback: .temporaryDirectory)` once the launch has read the library, in the wired run only, and closed at quit before the model stops. The fakes run opens none; `Tools/pr-media/fakes.sh door socket <url>` runs a command as the socket would and logs the reply line.
- **Rotation** (`AppModel+Rotation.swift`). The driver is made at launch when the library could be read, with the system sleep sensor (the fakes' `FakeSleepSensor`, "Sleep and Wake" in the Fakes menu), launched with `SessionStart.current()` when the displays are first known and before the first render state, told of every state change, display change, Pause All and Resume All, and stopped at quit. On fakes: a wake moved the Studio Display's playlist on, Pause All logged "no tick due", Resume All "counts from" the resume.
- **Diagnostics** (`AppModel+Diagnostics.swift`). Redacted of the home folder, `NSUserName()`, `NSFullUserName()`, the Steam account's name, every wallpaper's and library file's name and the files imported this session. Settings' General pane has a Diagnostics section: Copy Diagnostics and Save… (a Save panel, `Livepaper Diagnostics <date> at <hh.mm.ss>.txt`), with a spinner while the report is made (about 2 s, most of it `log show`) and "Copied" or "Saved" for 5 s. No new design-system component was needed.
- **Restart** (`ServiceRestart`, Core). The line says "Restarting the wallpaper service" while `recover(.restartAgent)` runs, then "Waiting for the wallpaper service" for up to `HeartbeatTiming.standard.grace`, or "Restarted recently; try again at <time>" when the host refused (its `lastAgentRestart`, new to `RenderHost`, did not move) or the service did not answer; the host's status has the line again when the service answers or that time comes. `FakeRenderHost` keeps the ten-minute gap too, and takes `agentRestartTime` to restart.
- **AppModel.swift** was at SwiftLint's 400 lines. M7's hooks there are one line each; `togglePauseAll`, `gridDidChange` and `resolveSection` moved to the files that use them.

## Out of scope

The screens and Settings rows, the Open panel, the window's drop zone, the app model, persisted playlists, assignments and mute (M6-screens.md). The soak, hot-plug loop, energy and the accessibility pass (M8-hardening.md). Signing, the DMG, Sparkle, the move prompt, the samples' notices (M9-release-engineering.md). The beta-seed select and deselect check (M10-1.0.md). App Intents, a Control Center widget, iCloud sync, Media Sync, a Share extension, time-of-day scheduling and Quick Actions (`docs/roadmap.md`: none ship). Editing the store when the user picked another wallpaper by hand (0003).
