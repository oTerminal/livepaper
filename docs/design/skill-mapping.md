# Design skill rules in SwiftUI

The design skills in `.agents/skills/` (`emil-design-eng`, `animate`, `apple-design`, `review-animations`, `make-interfaces-feel-better`) are written for CSS and React. Their values carry over unchanged; their syntax does not. This table is the translation. Load it with every design review, and express fixes in these terms.

Tokens live in `Packages/DesignSystem`. SwiftLint fails the build on raw animation or corner-radius values anywhere else (`.swiftlint.yml`).

| Skill rule | In SwiftUI |
|---|---|
| Never `transition: all` | `.animation(_:value:)` scoped to one value; never the value-less `.animation(_:)` |
| Never animate from `scale(0)` | Bare `.transition(.scale)` starts at 0 and is banned. Use `.scale(scale: 0.96, anchor:)` combined with `.opacity` |
| Popovers grow from their trigger | Pass `anchor:` to the scale transition; the menu-bar popover uses `.top` |
| Ease-out for enter and exit, never ease-in | `Motion.enter(_:)` and `Motion.exit(_:)`; `.easeIn` is a lint error |
| UI motion under 300 ms | `Motion.Duration` tokens; only `sheet` exceeds 300 ms |
| Exits quicker than enters | `Motion.exit(_:)` runs at 0.7x the enter duration |
| Springs as duration and bounce, bounce 0.1 to 0.3 only with momentum | `Motion.Spring.ui`, `.move` (bounce 0); `.momentum` (bounce 0.2) only after a gesture that carried velocity |
| Always interruptible | State-driven animations retarget from the current value. No `KeyframeAnimator` or `PhaseAnimator` on anything the user can trigger repeatedly (toasts, toggles, hover) |
| Animate transform and opacity only | Animate `scaleEffect`, `offset`, `opacity`, `blur`. Never animate a grid item's `frame` |
| No animation on keyboard-driven or very frequent actions | Changes triggered by a key press or global hotkey run in `Transaction(animation: nil)` |
| Press feedback: scale 0.96, on pointer down | A `ButtonStyle` reading `configuration.isPressed` |
| Stagger 30 to 80 ms | 0.04 s per item, at most 8 items; onboarding only uses 0.10 s per group |
| Icon swaps: opacity, scale 0.25 to 1, blur 4 to 0 | `.contentTransition(.symbolEffect(.replace))` for SF Symbols |
| Reduced motion means gentler, not none | With `accessibilityReduceMotion`, movement becomes a 0.2 s crossfade, bounce 0, no stagger, no hover autoplay |
| Concentric radii: outer = inner + padding | `ConcentricRectangle` with `.containerShape`; radius tokens where that does not apply |
| Materials encode hierarchy; never light on light | Glass only on the floating functional layer (sidebar, toolbar, popover, inspector controls). Never glass on glass: group neighbours in `GlassEffectContainer`. Wallpaper tiles are not glass |
| Materialise, don't fade | For a glass control that appears beside other glass in one `GlassEffectContainer` (a toolbar button, a split button's other half): `glassEffectTransition(.materialize)` with `glassEffectID`. A panel with words in it (popover, toast, drop plate) enters from 0.96 with opacity, anchored at its trigger: materialise blurs the text and grows from the centre (see `DECISIONS.md`, GlassPopover) |
| Image outlines | 1 px inside stroke, black at 10% in light mode, white at 10% in dark mode |
| Tabular numbers for changing values | `.monospacedDigit()` |
| Hit areas at least 40 x 40 | `.contentShape` sized independently of the icon |
| Momentum and rubber-banding | `DragGesture`'s `predictedEndTranslation`; a pure `rubberband()` function for overscroll |

The wallpaper crossfade (about 1 s) and the playback rate ramp on pause are content, not interface, and are exempt from the 300 ms rule.
