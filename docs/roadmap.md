# Livepaper: product roadmap and build plan

## Context

Livepaper is a free, open-source, native Swift live-wallpaper app for macOS 26+, in the spirit of wallper.app without the marketplace, licence server or accounts: you give it a video and it becomes your wallpaper, on the desktop and the lock screen. This document records the product decisions, then the architecture and the milestone order. Milestone specs live in `docs/specs/`, hard-to-reverse decisions in `docs/adr/`, and the project's vocabulary in `CONTEXT.md`.

Research that shaped it:
- Wallper's recurring bugs: playback not resuming after sleep (regressed three times), a 1-2 frame black flash at the loop seam (audio/video track length mismatch), menu-bar tint mismatch, library emptying on restart. Each is designed against below.
- macOS 14-27 has no public API for lock-screen video. The workable route is a private `com.apple.wallpaper` ExtensionKit extension, as Phosphene does (MIT, Swift 6, macOS 26+). The extension needs only the app-sandbox entitlement; App Groups break without a Team ID.
- Another project (MacWall) got an ad-hoc-signed wallpaper extension discovered and handshaking with WallpaperAgent. Nobody has shown a downloaded, quarantined, non-notarized copy working on a second Mac. That is our first test.
- AVFoundation cannot open WebM/MKV. Wallpaper Engine Workshop is ~41% plain video items, ~54% scenes (full renderer needed; out of scope permanently).

## Product decisions

| Area | Decision |
|---|---|
| Name / license | Livepaper, `app.livepaper.Livepaper`, MIT |
| OS / CPU | macOS 26+, Apple Silicon only, real Liquid Glass, no fallbacks |
| Distribution | GitHub Releases DMG, **not notarized** (no paid Apple account). Signed with our own self-signed certificate for a stable identity across updates; revisit only if the second-Mac test fails. First-launch "Open Anyway" instructions. Sparkle 2 with EdDSA. Repo goes public at the first milestone |
| Telemetry | None. "Copy diagnostics" export only |
| App shape | Menu-bar resident agent + library window (Dock icon only while open) |
| Menu bar | Custom glass popover: per-display current wallpaper, pause/next/mute, playlist picker, recents, Open Library, Settings |
| Library window | Glass sidebar (All, Favourites, Playlists, per-display Now Playing) + thumbnail grid with hover previews + trailing inspector. Whole window is a drop target |
| Wallpaper types | Video (mp4/mov/m4v; H.264/HEVC/ProRes) + GIF + Wallpaper Engine **video items only, permanently** |
| HDR | SDR only, permanently; HDR sources are tone-mapped |
| WebM/MKV/AVI/WMV/GIF | Converted once at import by a bundled LGPL ffmpeg helper built from source (no GPL parts), run as a separate process |
| Import | Drag & drop (window, Dock icon, menu bar item), Open panel, batch. Finder: "Open With", right-click Services/Quick Actions "Set as Live Wallpaper", URL scheme, CLI. WE folders recognised on drop. No URL or Steam downloading, no Share extension |
| Storage | Copy into an app-managed library; keep only the optimised copy (lossless remux when already H.264/HEVC, transcode only when required) |
| Library features | Favourites, rename, delete (Trash + undo), sort, search, file details, duplicate detection. No tags |
| Per-wallpaper settings | Fill (default) / Fit / Stretch, focal point, pan & zoom, volume. No dim/blur, loop crossfade, trim or speed |
| Audio | Muted by default, per-wallpaper volume, global mute |
| Displays | Per-display assignment keyed by display UUID + "apply to all"; independent playback |
| Rotation | Playlists with interval + shuffle; rotate on interval / wake / login, with a crossfade. No time-of-day scheduling |
| Pause rules | Each toggleable. Default on: desktop fully covered on that display, display asleep/locked, Low Power Mode. Default off: pause on battery |
| System integration | Launch at login, user-assignable global hotkeys. No App Intents, Control Center widget, iCloud sync or Media Sync |
| Menu-bar tint | Colour-matched still set as the system wallpaper, original restored when disabled. Only needed if the window renderer ends up being used; in extension mode macOS handles it |
| Rendering | Private wallpaper extension in v1.0 for desktop + lock screen + screensaver. **Extension only, no fallback renderer** |
| Contingency | If the downloaded build's extension does not load on a second Mac, the public desktop-window renderer becomes the main path and the extension becomes a bonus for source builders |
| Selection | One "Livepaper" entry in System Settings > Wallpaper, selected once by the app itself in onboarding (record 0003; the user's click is the fallback); the app drives what plays after that |
| Quit | Quit stops the live wallpaper: the extension holds the current wallpaper's poster as a still and releases its decoders. The system wallpaper stays "Livepaper", because no public API could select it again at the next launch (record 0003). Leaving Livepaper for good is a choice in Settings |
| First run | Short onboarding (drop a video / launch at login / Livepaper becomes the wallpaper) + 2-3 bundled CC0 sample loops with recorded provenance |
| Testing | TDD with Swift Testing on core logic; no UI snapshot tests; UI checked in a Gallery target, previews and manual runs; GitHub Actions CI |
| Build order | Engine spike, then design system, then screens |
| Execution | One PR per milestone. After the spike, independent lanes can run in parallel Conductor workspaces. Each milestone gets a spec in `docs/specs/` so it can be run with `/implement` (TDD at agreed seams, `/code-review` at the end, commit to the branch) |

## Engineering decisions

- Playback engine is `AVSampleBufferDisplayLayer` fed by two `AVAssetReader`s with an ever-increasing timestamp offset, not `AVPlayerLooper`. `AVPlayerLayer` fails silently inside the extension, and this removes the loop-seam flash by construction.
- Pause rules are one pure function from conditions to a playback decision. After wake, a watchdog checks frames are actually advancing and rebuilds step by step if not.
- Library metadata is a versioned JSON manifest written atomically by the app only. The extension reads a small `render-state.json` projection and is told to re-read it by Darwin notification. No SwiftData, no App Groups.
- Library lives in `~/Library/Application Support/Livepaper/`; the extension gets a read-only sandbox exception for that folder. The spike confirms this works, with Phosphene's approach (write into the extension's container) as the alternative.
- A small low-resolution hover-preview file per wallpaper counts as a derived artefact like the poster, not a second copy.
- XcodeGen `project.yml` + local Swift packages; Swift 6 mode, Approachable Concurrency, MainActor default for app/UI modules, nonisolated libraries (per `write-swift`). Code to a Swift 6.3 floor because hosted CI may lag Xcode 27 (to check at M0).
- English only in v1.0, with a string catalog. VoiceOver, Reduce Motion, Reduce Transparency and Increase Contrast are handled in the design system.
- Global hotkeys ship unassigned.
- No permission-gated (TCC) APIs anywhere, so nothing silently breaks when the signature changes.
## Architecture

```
project.yml                     # extension target included via targets/extension.yml (contingency switch)
Packages/LivepaperKit/          # one package, several library targets
Packages/DesignSystem/          # no domain dependencies; Gallery depends only on this
App/  WallpaperExtension/  Gallery/  CLI/
Helpers/ffmpeg/                 # build.sh, pinned version + sha256, configure flags, licences
Spikes/                         # own project.yml, throwaway, never imported by the product
Resources/Samples/ + PROVENANCE.md   docs/adr/   docs/specs/   docs/design/skill-mapping.md   CONTEXT.md
```

| Target | Isolation | Holds |
|---|---|---|
| `LivepaperCore` | nonisolated, Foundation only | Models, `Library` value type, `decidePlayback`, watchdog verdict, rotation reducer, display mapping, presentation geometry, `RenderState` codec, `LibraryStore` |
| `LivepaperImport` | nonisolated | Discover, WE `project.json` parser, fingerprint, probe, plan, `FFmpegTool`, normalise, artefacts, loop-seam validator |
| `LivepaperPlayback` | nonisolated | `LoopEngine` (actor on its own serial queue, since decode blocks), `PlaybackSupervisor`, layer tree, rate ramp |
| `LivepaperSystem` | MainActor | Sensors as `AsyncStream`s (displays, power, thermal, lock, sleep, occlusion), Carbon hotkeys, login item, tint service |
| `WallpaperAgentBridge` | nonisolated, ObjC shim | **All** private API: dlopen, type introspection, remote context, snapshot fix, caller validation, reconnect-spiral detector. Linked only by the extension |
| `RenderWindowHost` | MainActor | Desktop-level window per screen. **Built only if gate G1 fails** |
| `DesignSystem` | MainActor | Tokens, modifiers, components |

Key seams:

```swift
struct DisplayIdentity: Hashable, Codable, Sendable { let uuid: UUID }
func decidePlayback(_ c: PlaybackConditions, rules: PauseRules, host: HostCapabilities) -> PlaybackDecision   // .play | .pause(reason) | .suspend(reason)
func judgeProgress(before:after:expected:attempt:) -> WatchdogVerdict   // .healthy | .flush | .rebuildSurface | .rebuildPipeline | .restartAgent
func nextRotation(_ p: Playlist, _ s: RotationState, _ e: RotationEvent, rng: inout some RandomNumberGenerator) -> (RotationState, WallpaperID?)
protocol LibraryStore: Sendable { func load() throws -> Library; func save(_: Library) throws }
@MainActor protocol RenderHost: AnyObject {        // ExtensionHostClient now; DesktopWindowHost only if G1 fails; FakeRenderHost for tests
  var capabilities: HostCapabilities { get }
  func activate() async throws
  func apply(_ state: RenderState) async           // full state, idempotent
  var status: AsyncStream<RenderHostStatus> { get }
  func recover(_ level: RecoveryLevel) async
  func deactivate() async                          // stopped render state: the extension holds a still (record 0003)
}
```

- `PlaybackSupervisor` is the same code in either host: one `LoopEngine` per display, decoded once and fanned out to that display's surfaces (one per Space, plus lock screen, plus the Settings preview). Two video layers are created up front per surface, because a layer added later to a hosted context does not composite; crossfades and switches happen in place.
- Import stages: discover → fingerprint (SHA-256 dedupe before any conversion) → probe → plan (pure, table-tested: remux / AVFoundation transcode / ffmpeg then normalise) → convert → normalise (bound loop to the video track, reset edit lists, tone-map HDR) → artefacts (poster, tint still, hover proxy) → loop-seam validator → atomic commit from `.staging/`.
- App → extension: `render-state.json` (schema version, generation, per-display item + presentation + volume + user-paused, pause rules, app-sensed conditions with a 30 s expiry) plus a Darwin notification. Extension → app: a heartbeat packed into notification state, and a "spiral" signal asking the app to restart WallpaperAgent (at most once per 10 minutes). Occlusion is sensed in the app because the sandbox blocks window listing in the extension.

### Design system

Tokens carry the skills' values into SwiftUI: curves ease-out (0.23, 1, 0.32, 1), ease-in-out (0.77, 0, 0.175, 1), drawer (0.32, 0.72, 0, 1), ease-in banned; durations press 0.14 / hover 0.12 / popover 0.18 / panel 0.25 / sheet 0.35, exits at 0.7x; springs `ui` (0.3, bounce 0), `move` (0.4, 0), `momentum` (0.4, 0.2, only after a gesture with velocity); stagger 0.04 per item capped at 8; press scale 0.96; enter from 0.96 + opacity, never from 0; concentric radii via `ConcentricRectangle`; glass only on the floating layer, never glass on glass, tiles are not glass; keyboard- and hotkey-triggered changes get no animation; Reduce Motion turns movement into a 0.2 s crossfade. The wallpaper crossfade (~1 s) is content, not UI, and is exempt from the 300 ms rule.

`docs/design/skill-mapping.md` holds the CSS-rule → SwiftUI table and is loaded with every review. SwiftLint custom rules flag raw animation or radius literals outside `DesignSystem`.

Components: `SidebarRow`, `WallpaperTile` (poster goes live after a 200 ms hover dwell, one live preview at a time), `FitModePicker`, `VolumeSlider`, `FocalPointEditor`, `PanZoomEditor`, `SetOnDisplayButton`, `DetailsList`, `GlassPopover`, `DisplayNowPlayingCard`, `TransportCluster`, `PlaylistPicker`, `RecentsStrip`, `DropZoneOverlay`, `ImportProgressRow`, `Toast`/`UndoToast`, `EmptyState`, `OnboardingCard`, `HotkeyRecorder`, `LoginItemRow`, `PauseRuleToggle`, `StatusLine`.

Per-component loop: build in the Gallery with every state visible (switches for 0.1x slow motion, Reduce Motion, Reduce Transparency, Increase Contrast, light/dark, busy backdrop) → `review-animations` on the diff → `make-interfaces-feel-better` full review → both must approve → next-day look → record values in `DesignSystem/DECISIONS.md`.

## Roadmap

After M1, three lanes can run in parallel: A engine (M5), B design system and screens (M3, M6), C core, import, release (M2, M4, M9).

| # | Scope | Done when |
|---|---|---|
| M0 | `project.yml`, package skeletons, Makefile, SwiftLint rules, CI, `CONTEXT.md`, ADR template, repo public | `make gen build test lint` green locally and in CI |
| M1 | Time-boxed spike (matrix below) | ADR-0001 render host, ADR-0002 storage/IPC, ADR-0003 selection UX, ADR-0004 signing written; gate G1 decided |
| M2 | Core, test-first | Table tests pass for policy, watchdog, rotation (injected clock and RNG), display mapping, geometry, path containment, `RenderState` round-trip and migration |
| M3 | DesignSystem + Gallery | Every component approved by both review skills |
| M4 | Import pipeline + ffmpeg CI build | Fixture corpus imports correctly (audio longer than video, edit lists, VFR, HDR, WebM, GIF, WE folder, duplicates); validator finds no seam; cancel leaves no staging residue; CI publishes the ffmpeg artefact and source |
| M5 | Production engine, supervisor, render host | Spike tests S2-S7 pass again on product code; inspector preview reuses the engine |
| M6 | Screens on fakes, then wired | Manual script: drop → tile → hover preview → Set on display → delete → undo |
| M7 | Login item, hotkeys, Services entry, URL scheme, CLI, Dock/menu-bar drop, rotation driver, onboarding, diagnostics export | Each shown working end to end; login toggle always matches real status |
| M8 | Hardening | 24 h soak with lid cycles, zero unrecovered stalls; hot-plug loop; idle app ~0% CPU; 4K60 energy within the M1 budget (`Spikes/results/S2.md`, "Energy budget"); VoiceOver and keyboard pass |
| M9 | Release engineering: inside-out signing script, DMG, Sparkle + appcast, release workflow, samples + provenance, README install steps, move-to-Applications prompt | Second Mac installs from a real download; an N → N+1 Sparkle update keeps login item, extension and assignments |
| M10 | 1.0 | Checklist for testing each macOS beta seed exists |

Spike matrix (M1):

| # | Tests |
|---|---|
| S0, first | Minimal extension drawing a solid colour. Variants: ad-hoc and self-signed; from DerivedData and /Applications; hardened runtime on/off; **downloaded DMG on a second Mac via Open Anyway, then via `xattr -dr`**; after reboot; after a rebuild. Does a self-signed cert keep the login item and identity stable across builds? |
| S1 | Library location: Application Support with a read-only exception vs the extension's container. Any consent prompt? Notifications both ways |
| S2 | Gapless loop, first in a window then in the extension: 200 loops, no frame gap above 1.5x frame duration; energy vs `AVPlayerLooper` |
| S3 | Two displays, Spaces, fullscreen, Stage Manager, hot-plug, identical monitors, scale change |
| S4 | 20 lid cycles, long sleep, lock-screen playback, fast user switching, login before the app starts |
| S5 | Crossfade with two pre-created layers |
| S6 | Lock screen does not go grey in transitions (snapshot fix) |
| S7 | 50 rapid switches; spiral detection; WallpaperAgent restart without loops |
| S8 | Can the app select the "Livepaper" wallpaper itself, and restore the previous one on Quit (including a previous Aerial or dynamic wallpaper)? |

**Gate G1:** if S0 fails on the second Mac, the window renderer becomes the main path (M5 builds `RenderWindowHost` and the tint service) and the extension target is left out of release builds.

## Risks

| Risk | Handling |
|---|---|
| A macOS update breaks the private API, and there is no fallback renderer (a deliberate product decision) | All private API in one module; launch self-check; on failure show the poster still and say so in the popover; test each macOS beta seed; the `RenderHost` seam keeps a window renderer addable later |
| Downloaded non-notarized build's extension won't start | S0 on the second Mac decides G1 before anything else is built |
| Identity changes per build (login item orphaned, Gatekeeper re-prompts) | Self-signed certificate, verified in S0; reconcile login-item intent against real status at launch; extension relaunches itself after an app update |
| WallpaperAgent wedges | In-place switching, one flush at a time, spiral detector, rate-limited restart, manual "Restart wallpaper service" |
| Sleep/wake | Watchdog verifies frames advance and walks the rebuild ladder; policy recomputed 1 s after wake |
| Energy | One decode per display, compressed samples passed through to hardware decode, decoder released when suspended, per-display occlusion |
| Display hot-plug | Assignments keyed by UUID and remembered while unplugged; reconfiguration debounced |
| Sparkle without Apple signing | EdDSA required; sign inside-out including Sparkle's helpers; no hardened-runtime library validation; update path tested in M9 |
| App run from the download folder (translocation) | Detect and offer to move to /Applications before registering anything |
| The wallpaper store (`com.apple.wallpaper/Store/Index.plist`) is undocumented and can change with any macOS update | It is edited at two moments only, selecting in onboarding and leaving (record 0003); the code checks what it reads and falls back to the user's click in System Settings; the select/deselect check is on the beta-seed checklist |
| Restoring the previous wallpaper on Quit may be impossible for Aerial/dynamic wallpapers | S8 found that it is, and that selecting Livepaper again is impossible too. Quit holds a still instead (record 0003); the previous wallpaper, an Aerial included, comes back from a kept copy of the wallpaper store when the user leaves Livepaper |
| ffmpeg parsing untrusted files | Separate process, minimal build, no network; replaceable binary to satisfy the LGPL |

Unverified claims carried from research, to confirm at M0/M1: hosted CI image Xcode versions; the self-signed identity behaviour on macOS 27; Homebrew's 2026-09-01 cask policy (not relied on).

## Verification

- Every milestone: `make gen build test lint` locally and in CI.
- M1: each spike row produces a written result in its ADR, with `log stream` excerpts for WallpaperAgent, pkd and amfid where relevant. S0's second-Mac rows are run by hand from the checklist in `docs/specs/M1-engine-spike.md`.
- M2/M4: `swift test` on `LivepaperKit`; import fixtures checked by the loop-seam validator.
- M3: Gallery app reviewed per component with the two review skills.
- M5-M8: run the app; walk the manual scripts (drop → set → lock → sleep/wake → hot-plug → quit holds a still, relaunch resumes); 24 h soak log shows zero unrecovered stalls.
- M9: fresh download on the second Mac, then an update from the previous build through Sparkle.
