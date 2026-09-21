# M2: core, test-first

Write the decisions the app makes as pure code in `LivepaperCore`, tests first, before anything plays or draws. Lane C. See `docs/roadmap.md` (Architecture, Key seams) and decision records 0001 and 0002.

One input is not settled yet, and the rows that depend on it say so: record 0003 is only proposed. (Record 0001 is decided: gate G1 passed.)

## Rules

- `LivepaperCore` stays nonisolated and Foundation-only: no AppKit, AVFoundation, CoreGraphics display calls, file watching or clocks. Time, randomness, the home directory and the file system are parameters.
- Red, green, refactor at the seams below. Table tests with Swift Testing (`@Test(arguments:)`), one row per case, the row's name saying what it proves.
- Vocabulary is `CONTEXT.md`'s. A type called `Video`, `Screen` or `Thumbnail` is a review failure.
- Every persisted type carries a schema version. A version-1 fixture file is checked in with the tests and has to keep loading as the schema moves on; each later version adds its own.

## What the spike settled

- The library lives in `~/Library/Application Support/Livepaper/`. The app writes it; the extension reads it through a read-only sandbox exception (record 0002). Inside the extension's sandbox the home-directory APIs return the container, so nothing in Core may call them: `LibraryLocation` is built from a home URL the caller supplies.
- The extension may read that folder and nothing else. Any path that reaches it must be relative to the library root and stay inside it.
- App to extension: `render-state.json`, replaced atomically, then a Darwin notification. Extension to app: a Darwin notification whose 64-bit state is the heartbeat. Both directions work from inside the sandbox.
- A running timebase does not prove that pictures are reaching the display. Progress is measured in displayed pictures (record 0001, S4 helper).
- Replacing the app kills the running extension and nothing restarts it (record 0001). A missing heartbeat after launch is an ordinary state with a defined recovery, not an error.
- **Not settled:** record 0003 proposes that stopping does not switch the system wallpaper away. If it is accepted, the render state has a stopped form, in which the extension holds the poster and releases its decoders, and the extension must cope with no app running at all. Do not build the stopped form before 0003 is decided.

## Seams

| Seam | Signature (from the roadmap unless noted) | Table-tested for |
|---|---|---|
| Playback policy | `decidePlayback(_ c: PlaybackConditions, rules: PauseRules, host: HostCapabilities) -> PlaybackDecision` | Every pause rule on and off; user pause beats everything; locked display plays when the host can show the lock screen and suspends when it cannot; conditions older than 30 s are ignored; `.suspend` (release the decoder) versus `.pause` (keep it) |
| Watchdog | `judgeProgress(before:after:expected:attempt:) -> WatchdogVerdict`, where before/after are displayed-picture counts. The caller only asks about a surface that is on screen (a hidden one is throttled by the window server and would look stalled), so visibility is not a parameter | Healthy at half the expected pictures or more; the ladder `.flush` → `.rebuildSurface` → `.rebuildPipeline` → `.restartAgent` by attempt |
| Agent restart limit | `allowAgentRestart(last: Date?, now: Date, minimumGap: Duration) -> Bool` (new). Both the watchdog's and the heartbeat's `.restartAgent` go through it | Never twice within 10 minutes; the first is always allowed; the clock is an input |
| Rotation | `nextRotation(_ p: Playlist, _ s: RotationState, _ e: RotationEvent, rng: inout some RandomNumberGenerator) -> (RotationState, WallpaperID?)` | Interval, wake and login events; shuffle visits every wallpaper before repeating and never repeats across the reshuffle boundary; a playlist of one; a wallpaper deleted mid-rotation; seeded RNG gives a fixed sequence |
| Display mapping | `resolveAssignments(_ saved: [DisplayIdentity: Assignment], connected: [DisplayIdentity], applyToAll: Assignment?) -> [DisplayIdentity: Assignment]` (new) | Assignments survive a display being absent; a new display takes "apply to all" or nothing; two identical displays are two identities |
| Presentation geometry | `pictureRect(for p: Presentation, source: Size, surface: Size) -> Rect` (new; own `Size`/`Rect`, no CoreGraphics) | Fill, Fit, Stretch; the focal point stays in view when filling; pan and zoom clamp so the picture always covers the surface; portrait on landscape and the reverse |
| Path containment | `LibraryLocation(home:)`, `resolve(_ relative: String) throws -> URL` (new) | `..`, absolute paths, empty strings, symlink-looking names and paths that normalise outside the root are rejected; the staging folder is inside the root |
| Render state codec | `RenderState` `Codable`, `encode`/`decode` with version, generation, per-display wallpaper + presentation + volume + user-paused, pause rules, sensed conditions with a timestamp (and, if record 0003 is accepted, a stopped form) | Round trip; migration: the version-1 fixture keeps decoding as the schema moves on; a newer minor field is ignored; an unknown major version fails closed (the extension keeps what it shows); generation only increases |
| Heartbeat codec | `Heartbeat(generation: UInt32, flags: …).packed: UInt64` and back (new); flags include "a desktop surface is acquired", which is how the app learns that the user has selected Livepaper | Round trip of every flag; generation wraps safely |
| Heartbeat judgement | `judgeHeartbeat(last: Date?, now: Date, launchedAt: Date) -> RecoveryLevel?` (new). After an install or update the first extension instance is killed once by the next app launch and the agent does not reconnect (record 0001); the spike established no time window for it, so the rule is simply "no heartbeat after the grace period" | Silent during the grace period after launch; escalates while the heartbeat stays missing; quiet again as soon as one arrives |
| Library | `Library` value type: insert (the last step of an import), rename, favourite, delete, restore (undo), sort, search, duplicate lookup by fingerprint | Each operation returns a new value; delete then restore is the identity; search is case- and diacritic-insensitive |
| Library store | `protocol LibraryStore: Sendable { func load() throws -> Library; func save(_: Library) throws }`, `FileLibraryStore` writing a versioned JSON manifest atomically | Against a temporary directory: round trip, the version-1 fixture loads, a truncated file loads the last good manifest instead of an empty library (the Wallper "library emptied on restart" bug) |

`RenderHost`, `HostCapabilities` and `RenderHostStatus` are declared here as protocols and values only; `FakeRenderHost` lives in the test support target for M6 to build screens on.

## Done when

- The table tests above pass with `swift test --package-path Packages/LivepaperKit`, locally and in CI.
- `make gen build test lint` is green.
- No test sleeps, reads the clock, or touches a path outside a temporary directory.

## Out of scope

Anything that plays, draws, watches the file system or talks to macOS. Import (M4). The sensors that produce `PlaybackConditions` (`LivepaperSystem`, M5 and M7).
