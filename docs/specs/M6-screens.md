# M6: screens

Build every screen on M3-design-system.md's components: the popover, the library window, Settings, the empty states, the toasts and the import list, first on fakes, then wired. Lane B, after M3-design-system.md. See `docs/roadmap.md`'s product decisions, records 0002, 0003, 0005 and 0006, `CONTEXT.md`, `DECISIONS.md` and the specs for M2 to M5.

## Rules

- `App/` holds the model, the views and the wiring, and has no test target. Every decision a screen makes is a pure reducer or projection in `LivepaperCore`, or in `LivepaperImport` where it reads `ImportEvent`, table-tested under `swift test`. No snapshot tests.
- Screens compose `DECISIONS.md`'s components and add no token or raw animation or radius literal; `.swiftlint.yml` covers `App/`. A screen never reads the accessibility settings and never animates a key press.
- Vocabulary is `CONTEXT.md`'s, on screen and in code: no Video, Screen, Monitor, Thumbnail or Collection, and Import is never Add.
- Fakes first: `-fakes YES` runs the app on `FakeRenderHost`, an in-memory `LibraryStore`, a fake importer, two fake displays and M5-engine.md's fake sensors, reading `GallerySettings.swift`'s defaults so media records at 0.1x. Then wired to `FileLibraryStore`, `Importer`, `ExtensionHostClient` and `PreviewPlayer`; until M5-engine.md lands, only the fakes half is reviewed.
- The app is the one writer of `library.json`, `render-state.json` and the file added here. Everything persisted carries a `SchemaVersion`, is atomic and has a version-1 fixture (M2-core.md); `PersistedJSON` is Core-internal, so the new type lives there. The app target gains the other `LivepaperKit` libraries and `LivepaperTestSupport`.

## What earlier milestones settled

- **Core** (`M2-core.md`). Delete then restore is the identity, so undo is the old `Library` kept. `RenderState` carries per display the wallpaper, its files, `Presentation`, volume and `userPaused`, a stopped form and a rising generation.
- **Design system** (`DECISIONS.md`). No component knows a domain type. A tile goes live after a 200 ms dwell on a view the caller supplies, one across the grid. A toast lives 5 s (`ToastPresenter.lifetime`) and only an undo toast takes Command-Z.
- **Import** (`M4-import.md`). `discoverSources` gives `ImportCandidate`s, Wallpaper Engine items included (record 0005), and `SkippedSource`s with a reason. `Importer.events(importing:)` ends in `.imported` or `.duplicate(of:)`, the duplicate known from the fingerprint before any conversion, and dropping the stream cancels cleanly. `FFmpegTool.locate` waits for the helper (record 0006).
- **Engine** (`M5-engine.md`). `PreviewPlayer` plays an optimised copy or a hover preview and releases its decoder when hidden. `ExtensionHostClient: RenderHost` reports `.connecting`, `.live`, `.notSelected`, `.unavailable`, `.recovering(level)` and `.stopped`, and `recover(.restartAgent)` goes through `allowAgentRestart`. Volume 0 leaves the audio track unopened; a display absent from the state shows nothing. The developer menu, the display's name, the unassigned display and mute were left here.

## The app model

One `@Observable` `@MainActor` `AppModel` in `App/` holds the `Library`, an `AppState` (Core, new) and the transient state: selection, search, the undo record, the import list, the toast, host status, displays. It saves and applies, and stands behind `ImportLibrary` itself. `AppState` goes atomically to `app-state.json` beside the manifest (`LibraryLocation.appState`, new).

| `AppState` 1.0 | Holds |
|---|---|
| `version` | 1.0; M7-system-integration.md adds login-item intent and hotkeys at 1.1. An unknown major fails closed: the file is kept aside and the app starts on defaults |
| `assignments`, `applyToAll` | Display and `Assignment` pairs sorted by display, so the same state gives the same bytes |
| `playlists`, `rotation` | `[Playlist]` in the user's order; display and `RotationState` pairs, so a shuffled pass survives a relaunch. `Assignment`, `Playlist`, `RotationState` and `Library.SortOrder` gain `Codable` |
| `pauseRules`, `pausedDisplays`, `isMuted` | `PauseRules` at Core's defaults; the displays the user paused; global mute |
| `sortOrder`, `recents` | The grid's sort order; the last 8 wallpapers set on a display, newest first |

What the roadmap left open, decided here:

| Question | Decision |
|---|---|
| Render state | Pure `RenderState.make(library:state:connected:conditions:previous:)` in Core: `resolveAssignments`, each display's wallpaper (its assignment, or its playlist's `RotationState.current`) with the library's files and `Presentation`, `userPaused` from `pausedDisplays`, then `previous.next`. Applied on every change |
| Unassigned display | A wallpaper the library has lost counts as unassigned, and an unassigned display is left out of the render state, so the extension shows nothing. Its card reads "No wallpaper" with a Choose accessory; only onboarding (M7-system-integration.md) assigns without a click |
| Global mute | `isMuted` is the app's, projected as volume 0 on every display: no schema change, and the extension leaves the audio track unopened. `Wallpaper.volume` is kept |
| Pause | Pausing one display sets `pausedDisplays`: `.pause(.user)`, decoder kept. Pause All writes the stopped state through `deactivate()` (record 0003) and is not remembered, so the next launch is live |
| Next and Previous | `RotationEvent` gains `.next(at:)`, rotating at once and picking a new playlist's first wallpaper. Previous walks the session's history, in memory. Both are `canSkip: false` on a display showing one wallpaper |
| Delete | Library, assignments, apply-to-all, playlists, recents and rotation states lose it at once and are saved; a display showing it falls back to apply-to-all or nothing. The files go to the Trash when the undo toast ends; undo restores the library and the prior `AppState`. A launch inside those 5 s lets the sweep take the folder |

## Screens

| Screen | Composes, and what it does |
|---|---|
| Popover | `GlassPopover`, a `DisplayNowPlayingCard` per display with a `.plain` `TransportCluster` and a `PlaylistPicker`, `RecentsStrip`, a footer of Mute, Pause All or Resume All, Open Library, Settings and `StatusLine`. A card's status is the pause reason in words |
| Library window | Sidebar of `SidebarRowGroup`s (All, Favourites; a row per playlist, then New Playlist; Now Playing per connected display), a grid of `WallpaperTile`s in one `livePreviewScope`, the inspector, a toolbar with search, sort and Import. Tiles take a `PreviewPlayer` on the hover preview file; without one (M4-import.md) the poster stays. One tile is selected, arrows move it, Delete deletes; its context menu sets it on a display or All Displays, favourites, renames, changes playlists, deletes. The Dock icon follows the window |
| Inspector | `PreviewPlayer`, name, favourite, `FitModePicker`, `FocalPointEditor`, `PanZoomEditor`, `VolumeSlider`, `SetOnDisplayButton`, `DetailsList`, Delete. Targets are the connected displays; `.working`, `.done` for 1.5 s, then `.idle`. A playlist row shows name, interval (30 min by default), shuffle, count and a `SetOnDisplayButton`. `Library` gains `settingPresentation(_:for:)` and `settingVolume(_:for:)`; a display follows when the edit settles |
| Import | `DropZoneOverlay` over the whole window and an `ImportProgressRow` per candidate under the grid. A drop, Import or Command-O sends every URL through `discoverSources`, a Wallpaper Engine folder showing its preview and title. One import at a time, the rest waiting; cancel drops the stream. A duplicate's toast names the wallpaper it already is; a failure says why, with Retry |
| Settings | Four `PauseRuleToggle`s bound to `AppState.pauseRules`, `LoginItemRow`, a `HotkeyRecorder` each for Pause or Resume All, Next Wallpaper, Mute and Open Library, unassigned, and "Stop using Livepaper as wallpaper" behind a confirmation. The login, hotkey and leave rows talk to a `SystemServices` protocol declared in Core, answered by `FakeSystemServices`. The real one is M7-system-integration.md's |
| Status line | `StatusLine` from `RenderHostStatus`: an idle line for live ("Live on N displays"), not selected, unavailable or stopped; a working line while connecting, recovering or importing. `.recovering(.restartAgent)` shows `.serviceNotResponding`, its Restart calling `recover` |
| Toasts, empty states | A `Toast` with an undo title for a delete ("Deleted <name>"); a plain one for a duplicate, a skipped source, a failed import; one at a time. An `EmptyState` per sidebar section, plus no results and an unassigned display |

A finished row leaves after 5 s, and `sweepInterruptedImports` runs at launch before any import is accepted. `project.yml` copies `Helpers/ffmpeg/out/ffmpeg` into the bundle when present; `FFmpegTool.locate(replacement:bundled:)` gets that path and a replacement from the `FFmpegReplacement` default, the LGPL's relinking route. Without one those formats fail with `helperMissing`.

## Seams for test-first work

Swift Testing table tests under `swift test`, with an injected clock, `SeededGenerator` and the fakes. None touches a view.

| Seam | Tested as |
|---|---|
| `AppState` codec, the new `Codable` conformances | Round trip; the 1.0 fixture loads; a newer minor field is ignored; an unknown major throws; the same state gives the same bytes |
| `RenderState.make` | A wallpaper assignment; a playlist with and without a `current`; apply-to-all; unassigned; a lost wallpaper; a paused display; muted, so every volume is 0; a rising generation |
| Projections and selection | Now playing per display, with the card's status from `decidePlayback`'s reason; sidebar counts; the grid from section, search and sort; selection over click, arrows, delete |
| Undo record and pruning | A delete keeps the `Removal` and the prior `AppState` and prunes assignments, playlists, recents and rotation states; undo restores both |
| Set on display, Next and Previous | Set, applied, tick: `.working`, `.done` for 1.5 s, `.idle`, recents capped at 8. `RotationEvent.next` in `RotationTests`: rotates at once and sets `lastRotation` |
| Import list | Reducer over `ImportEvent`s and cancel: waiting, running with the stage's words and fraction, finished, failed with the reason, duplicate |
| Status line, the new `Library` edits | Every `RenderHostStatus` to a `StatusLineStatus`, an import taking the line; `Library.settingPresentation` and `settingVolume`, volume clamped |

## Manual script

On fakes, then wired; two displays where a row needs them.

| # | Step | Pass when |
|---|---|---|
| 1 | Launch on an empty library | Every card reads "No wallpaper"; the window shows its empty state |
| 2 | Drop three files, a Wallpaper Engine folder and a WebM; drop one again; cancel one | Five rows, one running; the Wallpaper Engine row has its preview and title; the WebM converts through the bundled helper; the duplicate's toast comes first; `.staging/` is empty |
| 3 | Rest the pointer on a tile; Set on display, then All Displays | Live after 200 ms, one at a time, never under Reduce Motion; working, done, idle; the display shows it; first in Recents |
| 4 | Change fit, focal point, pan and zoom, volume; Mute | The preview follows at once, the display when the edit settles; mute silences every display |
| 5 | Assign a playlist; Next twice, Previous once | The display steps through it; a display showing one wallpaper has both disabled |
| 6 | Pause one display; Pause All; Resume All | The card says paused; Pause All holds the still (record 0003); Resume All is instant |
| 7 | Delete the wallpaper a display shows, wait 5 s; delete another, undo | The display falls back; the first folder is in the Trash; the second is back on its display and playlist |
| 8 | Search, sort, close the window; quit and relaunch | The grid follows; the Dock icon goes with the window and Command-W leaves the app running; assignments, playlists, mute and pause rules come back |
| 9 | The fake host reports `.recovering(.restartAgent)`; wired, `killall WallpaperAgent` | The line says the service is not responding; Restart calls `recover`; the line returns to live |
| 10 | Settings: each pause rule, the login item, a hotkey, leaving | Each row shows the seam's state; the fake login item flips at once; Command-Q is a conflict |
| 11 | VoiceOver and the keyboard over every screen | Every control read with `DECISIONS.md`'s words; nothing animates from a key press |

## Media for the PR

Screenshots, cropped, of: the popover live, paused, unassigned, not selected and degraded with Restart; the window with a selection; the inspector idle, working and done; each empty state; the import list's four row states; both toasts; Settings' login row in its four states. Videos at 0.1x, GIF inline and MP4 beside it: a tile preview going live; the drop overlay; Set on display; a delete with its toast and undo; the popover opening. `Tools/pr-media/shot.sh` and `record.sh` take the app's window by name; `winid.swift` takes only layer-0 windows, so the popover needs a layer argument.

## Done when

- The seam tests pass with `swift test --package-path Packages/LivepaperKit`, locally and in CI; `app-state-v1.0.json` is checked in; `make gen build test lint` is green.
- The script passes on fakes and, with M5-engine.md landed, wired.
- M5-engine.md's developer menu is gone but for "Log playback metrics", which M8-hardening.md and M10-1.0.md turn on; the ffmpeg helper is in the built app; and a WebM imports in a real run.
- Every screen has a preview, and the media above is in the PR.

## As built

What M6 decided or found on the way, for M7-system-integration.md, M8-hardening.md and M10-1.0.md to build on. Names are quoted from the code.

### Core and Import

- **`AppState`** (`AppState.swift`) is the table above at 1.0, with `app-state-v1.0.json` and `app-state-v1.9-newer-minor.json` checked in. `FileAppStateStore` answers `AppStateLoad`: `.loaded`, `.missing`, or `.keptAside(url, version)`, the unreadable file moved to `app-state.kept-aside.json` (replacing an earlier one), so the next save cannot overwrite what a newer Livepaper wrote. A playlist's interval must lie within `Playlist.intervalLimits` (1 s to a year) or the file does not decode. M7 adds its 1.1 fields with `decodeIfPresent`.
- **Every edit is an `AppState` or `Library` function**, table-tested: `assigning`, `assigningToAll` (sets apply-to-all and clears every display's own assignment, connected or not), `choosingPlaylist` ("No Playlist" keeps the wallpaper the display shows as a plain assignment), `unassigning`, `settingPaused`, `rotating`, `steppingBack`, `removingWallpaper`, the playlist edits, `shows(_:on:)` for Set on Display's checkmark, `playbackVolume` (mute's rule, shared by the render state and the inspector's preview), `Library.settingPresentation` and `settingVolume`.
- **`RenderState.make`** (`Showing.swift`) is the one way a render state is made. A playlist display shows its rotation's `current`, else what rotation would show from `position`, else the playlist's first wallpaper still in the library. It answers nil when nothing changed; a stopped previous gives a live state.
- **Rotation.** `RotationEvent.next(at:)` rotates at once. `RotationHistories` holds each display's session history for Previous (`next(on:…)`, `previous(on:…)`, `forget(changedFrom:to:)`); a display that stops showing a playlist loses its history and its rotation state.
- **Screens' projections**: `nowPlaying` (the card's status from `decidePlayback`'s reason: "Paused", "Paused: desktop covered", "Paused: display asleep", "Paused: locked", "Paused: Low Power Mode", "Paused: on battery"; Pause All reads "Paused"), `sidebarCounts`, `libraryGrid` and `emptyGrid`, `GridSelection` (click, arrows running on across rows, Home/End, a delete moving on to the next tile, a playlist's section starting with nothing selected so the inspector shows the playlist), `LibrarySection.resolved(displays:playlists:)` and `afterCreating(_:)`, `SetOnDisplayFeedback` (working, done for 1.5 s, idle; `refused()` goes straight back to idle), `statusLine(host:showing:isPausedAll:importing:)` → `StatusLineContent`, which the app maps case for case onto the design system's `StatusLineStatus`.
- **`SystemServices`** (Core, `@MainActor`, M7 keeps its shape): `loginItem`, `setOpenAtLogin(_:) -> LoginItemStatus` (answered in the same turn), `openLoginItemsSettings()`, `hotkeys`, `availability(of:for:) -> HotkeyAvailability` (`.free`, `.usedBy(action)`, `.takenElsewhere`), `assign(_:to:)`, `leaveLivepaper()`. `KeyCombination.Modifiers` uses the design system's bits. Both runs use `FakeSystemServices` until M7.
- **The import list** (`ImportList`, LivepaperImport) runs one import at a time and returns effects: `.start`, `.cancel`, `.check` (a new row is looked up at once through `ImportRunning.existingWallpaper(for:)`, so a file already in the library becomes a duplicate before its turn and before any conversion), and `.toast(ImportToast)`. A source already in the list (waiting, running or failed) is refused with "“<name>” is already in the import list". Finished and duplicate rows leave after 5 s, and so does a failed row that Retry cannot help; one Retry can help stays, with "Remove from List". `progress` counts the batch ("Importing 2 of 5"). The words are `stageWords` (Checking, Reading, Converting, Optimising, Checking the loop, Making the poster, Finishing), `ImportToast`, `importFailureWords` and `skipWords`, all pinned by tests.
- **Test support**: `FakeSystemServices`, `InMemoryLibraryStore`, `InMemoryAppStateStore`, `FakeImporter` (fingerprint = SHA-256 of the path; "fail" in a name fails at probe; webm, mkv, avi, wmv and gif go through the convert stage), and `FakeRenderHost`'s `applyDelay` and `liveAfter`.

### The app

- `App/Model` (`AppModel`, the one writer of `library.json` and `app-state.json`, and `ImportLibrary` itself), `App/Shell` (the menu-bar item and its glass panel, the windows, launch options, the Fakes menu and remote), `App/Screens/{Popover,Settings,Library}`, `App/Views` (`PreviewPlayerView`, `PosterImage`, `WallpaperPoster`, `DrawnPoster`). M5's developer menu is gone: the menu-bar item's secondary-click menu holds "Log Playback Metrics" and "Quit Livepaper", and the probe now lasts the session through Pause All and Resume All.
- **Decided here**: a recent in the popover sets it on All Displays; "New Playlist…" from a card makes "New Playlist" and opens the library on it; a playlist's Rename and Delete live on its sidebar row; Settings has two panes, General and Shortcuts; when `library.json` cannot be read the app writes nothing and says so (the library window, the popover's cards, Mute, Pause All and the pause rules); the Open panel is a sheet on the library window when that window is key, otherwise a panel of its own.
- **The first wired launch** after M5 finds no `app-state.json`, so every display is unassigned and shows nothing until a wallpaper is set: M5 kept assignments only in `render-state.json`, and they are not carried over.
- **The ffmpeg helper** is copied from `Helpers/ffmpeg/out/ffmpeg` into `Contents/MacOS` by a post-build phase and ad-hoc signed as `app.livepaper.Livepaper.ffmpeg` (user-script sandboxing is off for it); without one the build still passes. `FFmpegTool.locate` takes the `FFmpegReplacement` default as the replacement's path.
- **The fakes run**: `-fakes YES` (empty library), `-fakeLibrary seeded`, the Gallery's switches from launch arguments only (`-slowMotion YES`, `-reduceMotion`, `-reduceTransparency`, `-increaseContrast`, `-appearance Dark|Light`), a "Fakes" submenu (the host's seven statuses, the conditions, the login item's four states, the popover's pauses and playlist, Import Sample Files), and a remote for scripts, `Tools/pr-media/fakes.sh <verb …>`, that only a fakes run hears (`-fakesRemote <name>` with `LIVEPAPER_FAKES=<name>` keeps two runs apart). `winid`, `shot.sh` and `record.sh` take a process ID for the app and a layer: the popover's panel is layer 101.
- **Log lines** (`app.livepaper.Livepaper`, category `app`, `AppLog.swift`): `app: launched <wired|on fakes>`, `app: swept <n> interrupted imports`, `app: library not read, so nothing will be written: <error>`, `app: app state kept aside at <path> (version <v|unreadable>), starting on defaults`, `app: render state <n> made, <k> displays showing`, `app: pause all, render state <n> stopped`, `app: resume all`, `app: import finished, wallpaper <UUID> "<name>"`, `app: import finished, duplicate of wallpaper <UUID> "<name>"`, `app: import failed for "<name>": <error>`, `app: deleted wallpaper <UUID> "<name>", undo offered`, `app: delete of wallpaper <UUID> undone`, `app: wallpaper <UUID>'s folder moved to the Trash`, `app: choosing files to import, <in a sheet on the library window|in a panel of its own>`, `app: quit, stopped after render state <n>`.
- **Keys and prompts**: the grid deletes with `onDeleteCommand` (Delete, forward delete, Edit > Delete) and File > Delete Wallpaper (⌘⌫) acts on the grid's selection only while the grid has focus; the rename and New Playlist prompt is a sheet whose field has focus, its name judged by Core's `acceptedName(_:)`. `PreviewPlayer` gained `backgroundColor` (default black, Fit's bars): the tile's live preview is clear behind, so the poster shows until the first frame and nothing dips dark.
- **Found on screen and fixed in the design system**: a `HotkeyRecorder` is as wide as its field and the clear button's slot in every phase, and a caption too wide for it hangs from the field's trailing edge (`HotkeyRecorderCaption`, tested), so a conflict no longer moves the field in Settings' trailing-aligned rows. `SidebarRow` and `WallpaperTile` carry their button's action as an `accessibilityAction`: the element each makes for its label with `accessibilityElement(children: .ignore)` is not the button's and had no press.
- **The design system grew** where screens needed a control rather than inventing one: `CompactTextButton` is public, `PlaylistPicker` has a `.plain` style for inside the popover, `SidebarRowGroup` takes a context menu per row, and `LabelButton`, `LabelToggle`, `SymbolButton` and `FavouriteToggle` share FitModePicker's pill (14%, 30% under Increase Contrast); each has its `DECISIONS.md` entry and Gallery page.

### Developer notes

- ExtensionKit does not load an extension from `/private/tmp` (pkd logs `-10814`); run a copy from under the home folder. Unregistering the extension that is running lets WallpaperAgent fall back to a picture wallpaper, which deselects Livepaper until it is chosen again in System Settings.
- A window capture of the glass popover in light mode comes out blank (nothing behind the glass); capture it in dark mode.
- Synthetic `CGEvent` drags do not start a Finder drag session; the drop was checked with a real drag.
- In zsh `log` is a builtin: read logs with `/usr/bin/log`.
- Keys for an on-screen check go to the app's process (`CGEvent.postToPid`), so a ⌘Q meant for a recorder cannot reach another app. `AXShowMenu` opens a context menu only while the app is frontmost.
- Every restart of WallpaperAgent, a click on Restart included, waits out `agentRestartGap` (10 minutes) after the last one, and a refused one is logged. A check that needs the host to restart the agent waits for the gap, and so does a build swap, whose install hazard needs that restart.
- This Mac shows scroll bars always, so the popover's recents strip shows its scroller once it holds more than fit: `.scrollIndicators(.hidden)` honours that setting, and is kept, since a mouse user has no other way across.

### The manual script

Run on fakes, then wired on one MacBook display (macOS 27.0) on 2026-09-23; the second display's rows are the fakes' Studio Display.

| # | Result |
|---|---|
| 1 | Pass. Fakes: both cards read "No wallpaper" with Choose…, the window "No wallpapers yet". Wired: the one card reads "No wallpaper" (the library already held M5's six wallpapers) |
| 2 | Pass, wired. Three files, a Wallpaper Engine folder, a WebM and a file with audio dropped from Finder: each imported, the Wallpaper Engine item under its project's title; the WebM stored as HEVC through the bundled helper; a file imported again became a duplicate of its wallpaper before any conversion; a 4K WebM cancelled at 3% left `.staging/` empty and no ffmpeg running |
| 3 | Pass, wired. Resting on a tile, its preview went live and its neighbour stayed a poster; Set on Display went done then idle (on the real host the working phase is too short to see); the extension showed it; first in Recents |
| 4 | Pass for fit, wired: the preview letterboxed at once, the render state followed once the edit settled. Mute set volume 0 in the render state |
| 5 | Pass, wired: a three-wallpaper playlist, Next, Next, Previous stepped the display through it |
| 6 | Pass, wired: one display's pause (`pause.user`), Pause All (the still, record 0003), Resume All live 2 ms later with the display's own pause kept |
| 7 | Pass, wired: the display fell back to nothing, the folder went to the Trash after the toast; a second delete undone was back on its display |
| 8 | Pass, wired: search and sort; ⌘Q wrote the stopped state; the relaunch was live without a click on the same playlist, muted, sorted by name. The Dock icon and ⌘W were checked on fakes |
| 9 | Pass. Fakes: `.recovering(.restartAgent)` shows the service not responding with Restart. Wired: after `killall WallpaperAgent` launchd started the agent at once, the agent started the extension, and the host read `notSelected` for 0.1 s, then live. With the extension held silent (SIGSTOP), the host climbed to `.recovering(.restartAgent)` in 45 s and the popover said the service was not responding, with Restart. Within 10 minutes of the last restart both the automatic restart and the click were refused and logged (`not restarting WallpaperAgent (user): restarted less than 10 minutes ago`), so Restart reaches `recover`; once the gap had passed the host restarted the agent itself and was live 0.29 s later, and a resumed extension put the line back to "Live on 1 display" |
| 10 | Pass, wired: each pause rule; the fake login item's four states; ⌘Q typed into a recorder is a conflict ("⌘Q is already used by macOS or another app") and recording goes on, Escape ends it. The conflict's caption had widened the recorder and moved its field 60 pt left of the other rows' fields: fixed below. "Stop Using Livepaper as Wallpaper…" asks first, and Cancel leaves everything as it was |
| 11 | Keyboard, wired: pass. The arrows run on across rows, Home and End go to the ends and a key at either end stays; Delete, forward Delete and ⌘⌫ delete the selected tile, and ⌘⌫ in the search field only edits its text; the name prompt opens with focus in its field, Return submits and Escape cancels; a context menu opens by the show-menu action and is worked from the keyboard; Tab walks both Settings panes. Recorded at 0.1x, the selection ring moves in one frame. Accessibility: the tree over every screen reads `DECISIONS.md`'s words, and the playlist picker and pause rules found earlier are fixed. An Accessibility press on a sidebar row or a tile did nothing, so VoiceOver could not choose a section, New Playlist or a tile: fixed below. Open: Tab focus on a Settings switch lands on AppKit's switch, which reports no label, beside the labelled checkbox SwiftUI exposes. What VoiceOver says there, and the spoken walk itself, are left to M8-hardening.md's accessibility gate |

## Out of scope

The rotation driver, the login item, hotkeys, the Services entry, the URL scheme, the CLI, a drop on the Dock icon or the menu-bar item, onboarding and selecting Livepaper, leaving through the real wallpaper store, the diagnostics export (`M7-system-integration.md`). The soak, the energy numbers and the accessibility release gate (`M8-hardening.md`). Signing, the DMG with the LGPL notices, Sparkle and the samples (`M9-release-engineering.md`), and the beta-seed checklist (`M10-1.0.md`). The engine and the extension (`M5-engine.md`). Multiple selection, tags and a per-wallpaper mute are not built.
