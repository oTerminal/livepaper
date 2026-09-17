# M3: design system and Gallery

Build every component the screens need, in isolation, before any screen exists. Lane B; nothing here depends on the engine spike. See `docs/roadmap.md` (Design system) and `docs/design/skill-mapping.md`.

## Rules

- Everything goes in `Packages/DesignSystem` and `Gallery/`. The package has no domain dependencies: it does not import `LivepaperKit`, and no type from `CONTEXT.md` appears in a component's API. A component that shows a wallpaper takes an image and a title, not a `Wallpaper`.
- Motion, radius, spacing and material values exist only as tokens. SwiftLint already fails raw animation and corner-radius literals outside the package; keep it that way when adding tokens.
- Glass goes on the floating functional layer only (sidebar, toolbar, popover, inspector controls). Never glass on glass: neighbours share a `GlassEffectContainer`. Wallpaper tiles are not glass.
- Changes triggered by a key press or a global hotkey do not animate. With Reduce Motion, movement becomes a 0.2 s crossfade, bounce 0, no stagger, no hover autoplay.
- macOS 26 floor, real Liquid Glass, no fallbacks. English only, strings in the package's string catalog.
- One component per PR-sized commit. A component is not done until both review skills approve it (loop below).

## Tokens

Already present: `Motion` (durations, curves, springs, enter/exit helpers). Add, each with tests that pin the values the skills prescribe:

| Token | Holds |
|---|---|
| `Radius` | The radius scale, and the concentric rule (outer = inner + padding) for where `ConcentricRectangle` does not apply |
| `Spacing` | The spacing scale used by every stack and padding |
| `Stagger` | 0.04 s per item, capped at 8 items; onboarding groups at 0.10 s |
| `Press` | Scale 0.96 on pointer down, as a `ButtonStyle` |
| `Outline` | 1 px inside stroke for images: black 10% in light, white 10% in dark, stronger with Increase Contrast |
| `LayerMaterial` | Which material each layer of the interface uses, and the Reduce Transparency substitutes (not `Surface`, which `CONTEXT.md` owns, and not `Material`, which is SwiftUI's) |

## Components

`SidebarRow`, `WallpaperTile`, `FitModePicker`, `VolumeSlider`, `FocalPointEditor`, `PanZoomEditor`, `SetOnDisplayButton`, `DetailsList`, `GlassPopover`, `DisplayNowPlayingCard`, `TransportCluster`, `PlaylistPicker`, `RecentsStrip`, `DropZoneOverlay`, `ImportProgressRow`, `Toast` and `UndoToast`, `EmptyState`, `OnboardingCard`, `HotkeyRecorder`, `LoginItemRow`, `PauseRuleToggle`, `StatusLine`.

Behaviour that is easy to get wrong:

- `WallpaperTile`: the poster goes live after a 200 ms hover dwell; one live preview at a time across the whole grid; the live preview is handed in as a view by the caller, so the package never touches AVFoundation.
- `FocalPointEditor` and `PanZoomEditor`: drags follow the pointer with no animation; release settles with `Motion.Spring.momentum` only if the gesture carried velocity; values are normalised (0 to 1), never points.
- `UndoToast`: interruptible; a second toast replaces the first in place rather than queueing.
- `HotkeyRecorder`: ships unassigned; shows conflicts; Escape cancels, Delete clears.
- `LoginItemRow`: renders four states (off, on, needs approval in System Settings, not found); it is told the state, it does not ask `SMAppService`.
- `StatusLine`: the one place a degraded render host is reported ("Wallpaper service not responding. Restart").

## Gallery

One page per component, every state visible at once, with a toolbar of switches: 0.1x slow motion, Reduce Motion, Reduce Transparency, Increase Contrast, light/dark, and a busy backdrop (a photo behind the glass). The switches override the environment for the page; they do not change system settings.

## Seams for test-first work

Tests (Swift Testing) cover logic, not pixels. No snapshot tests.

| Seam | Tested as |
|---|---|
| Token values | Table tests pinning each value to the number in `skill-mapping.md` |
| `rubberband(offset:limit:)` | Pure function: monotonic, bounded, identity at 0 |
| Stagger delay for index n | Pure function: linear to the cap, flat after it |
| Hover dwell state machine (`WallpaperTile`) | Reducer over enter/exit/tick events with an injected clock: goes live only after 200 ms, never two live at once |
| Toast replacement | Reducer: show, replace, undo, expire |
| `HotkeyRecorder` key handling | Reducer over key events: record, conflict, cancel, clear |
| Focal point and pan/zoom maths | Pure functions: normalised value to and from view coordinates, clamping so the picture always covers the frame |

## Per-component loop

Build it in the Gallery with every state visible → run `review-animations` on the diff → run `make-interfaces-feel-better` (full review) → both must approve → look again the next day → record the values chosen, and why, in `Packages/DesignSystem/DECISIONS.md`.

## Done when

- Every component above is in the Gallery and approved by both review skills.
- `make gen build test lint` is green locally and in CI.
- `DECISIONS.md` has an entry per component.
- VoiceOver reads every control in the Gallery sensibly, and every control is reachable by keyboard.

## Out of scope

Screens, navigation, anything that knows what a wallpaper is, the wallpaper crossfade (content, not interface; it belongs to M5).
