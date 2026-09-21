# Design system decisions

The values chosen for each token and component, and why. The rules they answer to are in `docs/design/skill-mapping.md`; the skills are in `.agents/skills/`. Add to an entry when a value changes; do not rewrite history.

Every component reads accessibility through `@Accessibility`, never the system environment values, so the Gallery can override them for one page. Two resolvers build every animation, and both apply the Gallery's slow motion:

- `accessibility.animation(_:)` is for movement. Under Reduce Motion it becomes the 0.2 s crossfade, and the component also drops the movement itself (opacity-only transition, no throw, no stagger).
- `accessibility.fade(_:)` is for changes of opacity or colour only. Reduce Motion leaves it alone: reduced motion keeps fades and drops movement. Without this split a 0.12 s hover wash became 0.2 s under Reduce Motion, and exits stopped being quicker than enters.

`accessibility.symbolReplace` is the symbol-replace content transition, or a plain fade under Reduce Motion (the system honours only the real setting, not the Gallery's override).

Changes made from a key press run inside `withoutAnimation`, which also switches off a component's own `.animation(_:value:)`. Where one control answers both a click and a key press (a default button, a focused button pressed with Space), `withoutAnimationIfKeyPress` decides from the current event, so the rule does not rest on the caller.

Every `.animation(_:value:)` sits on the one effect it drives, never on a container that also holds the caller's content. Hover fades run `Motion.enter` in and `Motion.exit` out. Focus rings follow the control's drawn shape (`contentShape(.focusEffect, …)`), not its 40 pt hit rectangle.

Reviewed on 2026-09-21 with `review-animations` and `make-interfaces-feel-better` (full mode); the findings are folded into the entries below. Still owed: the next-day look, and a pass at 0.1x by a person, which no static review replaces.

## Tokens

### Radius
- Scale `control` 8, `tile` 12, `card` 16, `panel` 20. Each step is 4 pt, so the common paddings (4, 8) land on another step when nesting: a 12 pt poster 8 pt inside a card gives the 20 pt `panel`, the worked example in make-interfaces-feel-better.
- `outer(inner:padding:)` is the concentric rule, for where `ConcentricRectangle` cannot be used (the outermost shape, or a shape outside a rounded container). Past about 24 pt of padding the layers read as separate surfaces and each radius is chosen on its own.

### Spacing
- A 4 pt grid (4, 8, 12, 16, 24, 32) with one 2 pt `hairline` step for optical corrections only, such as icon-side padding = text-side padding minus 2.
- `minimumHitArea` 40: the dense-desktop minimum from make-interfaces-feel-better, not the 44 pt touch value.

### Stagger
- 0.04 s per item, inside the skills' 30 to 80 ms band, and capped at 8 items so the last item of any list starts within 0.28 s. Items past the cap arrive with the eighth.
- Onboarding groups use 0.10 s: infrequent, staged, and the one place make-interfaces-feel-better's ~100 ms group stagger applies.
- Reduce Motion: every delay is 0.

### Press
- Scale 0.96 on pointer down, always; never under 0.95. The press lands with no animation and the release eases out over `Motion.enter(Duration.press)` (0.14 s, inside the skills' 100 to 160 ms band for press feedback; the 0.7x exit would be 98 ms, just under it).
- `isStatic` opts out of the movement, not of the feedback: a static control dims to 70% instead, so pointer-down is always acknowledged.
- Under Reduce Motion every control is static.

### Outline
- 1 pt, inside the image's edge, pure black at 10% in light mode and pure white at 10% in dark. Never a tinted neutral: it reads as dirt on the image edge.
- Increase Contrast raises it to 35%, same colour. The skills give no number; 35% is a first choice, roughly three times the standard strength, and has not yet been judged against real posters with Increase Contrast on.
- Drawn as a double-width stroke clipped to the shape, because `ConcentricRectangle` is not insettable.

### LayerMaterial
- `content` is the window background; `tile` has no surface of its own (the poster is the surface); `sidebar`, `toolbar`, `popover` and `inspectorControl` are glass. That is the whole of the floating functional layer.
- Reduce Transparency replaces glass with an opaque control background and a separator edge (2 pt under Increase Contrast), following apple-design's "near-solid backgrounds with a defined, contrasting border".
- Named `LayerMaterial` because `Surface` belongs to `CONTEXT.md` and `Material` to SwiftUI.

### Motion (added in M3)
- `reducedCrossfade`: 0.2 s ease-out, the Reduce Motion replacement for any movement. `resolve(_:reduceMotion:)` picks between them. Reduced motion means gentler, not none.

- `enterScale` 0.96: what an element enters from and leaves to, with opacity, anchored at its trigger. Never from 0.
- `Spring.momentum(initialVelocity:)`: the same 0.4 s, bounce 0.2 spring, started at the speed the gesture was released at. Without it a thrown element stops dead and sets off again, which reads as an ease-in at the very moment the user is watching.

### rubberband(offset:limit:) and unrubberband
- Apple's formula from the Designing Fluid Interfaces sample, constant 0.55: `offset * limit * c / (limit + c * |offset|)`. Zero at zero, monotonic, never reaches `limit`.
- `unrubberband` is its inverse, so an element picked up while still past its edge continues from where it is instead of jumping.

## Components

### WallpaperTile
- Not glass: tiles are content. Elevation is two fixed shadows behind the poster (12% radius 4, and 22% radius 10); hover fades the deeper one in over `Duration.hover` and out at 0.7x. Only an opacity animates: a shadow whose radius animates is re-blurred every frame, under a pointer that sweeps the grid constantly, next to live video.
- Selection is a 3 pt accent ring 2 pt outside the tile, concentric with it (12 + 5 = 17 pt), because selection is state and state gets a border. It never animates.
- The poster goes live after a 200 ms dwell, decided by `HoverDwell` (tested), and `LivePreviewCoordinator` shares one dwell across the grid so two tiles are never live. The preview crossfades in place over `Duration.panel` and leaves at 0.7x; the animation is scoped to the preview alone, so a grid reflow in the same update cannot animate a tile's frame. The caller supplies the preview as a view, so the package never touches AVFoundation.
- Reduce Motion disables hover autoplay entirely (`livePreviewScope` switches the coordinator off).
- No hover scale: a grid of tiles is swept constantly, and movement on every pass would be noise.
- Press is 0.96 like every other control. The focus ring follows the poster, not the title.

### FocalPointEditor
- The value is a `UnitPoint`, 0 to 1 on each axis; the maths (`FocalPointMath`, tested) converts to and from the letterboxed picture and clamps to it.
- The handle follows the pointer inside `withoutAnimation`. On release, above 300 pt/s the handle carries on a quarter of the way to SwiftUI's projected end with `Spring.momentum(initialVelocity:)`, starting at the pointer's speed; below it, nothing animates. A quarter, because a full throw sends a precise control flying. Under Reduce Motion there is no throw: the handle stays where it was let go.
- Cross-hairs are there at once on pointer down and fade out on release (`Motion.exit(Duration.hover)`). They are white over a wider dark stroke, as the handle has its shadow, so they hold over any picture. The handle is 24 pt drawn, 40 pt hit area.
- Arrow keys nudge by 0.01 without animation. VoiceOver: adjustable left/right in steps of 0.05, with "Move up" and "Move down" actions.

### PanZoomEditor
- Pan is a fraction of the frame and zoom a factor from 1 to 4, matching how the app stores a presentation. `PanZoomMath` (tested) clamps both so the picture always covers the frame, with the same focal-point rule as the core's `pictureRect`.
- The picture is laid out once at zoom 1 and then moved with `scaleEffect` and `offset` only, so nothing animates a frame.
- Dragging past an edge rubber-bands, up to 60 pt; pinching past 1x or 4x gives by up to 0.25 in the same way. Release: with velocity, `Spring.momentum(initialVelocity:)` and a quarter of the projected throw; at rest but overscrolled, `Spring.ui` (no bounce, because nothing was moving).
- Picking the picture up mid-throw continues from where it is on screen: an `Animatable` modifier reports the in-flight pan and overscroll, and `unrubberband` turns the overscroll back into a drag. Repeated flicks are how a zoomed picture is crossed, so this path is the normal one.
- Reduce Motion: no throw, a plain stop at the edges with nothing to spring back, and Reset jumps.
- Reset by click animates with `Spring.move` (0.4 s: the token for an element changing position; a spring's duration is where it settles, and most of the travel is over well inside 300 ms). By Space or Return it does not animate. Arrow keys pan by 0.02 and + / - zoom by 0.1, without animation.
- The zoom slider pulls pan back as it zooms out, so what VoiceOver reads is what is on screen.

### GlassPopover
- Glass, `Radius.panel`, and a `containerShape` so children can be concentric. `contentPadding` is 12 pt by default, and 4 pt for cards of `Radius.card` (20 = 16 + 4). Content inside must not be glass.
- Enters from `Motion.enterScale` with opacity, anchored at the edge that touches the trigger, over `Duration.popover` (0.18 s); leaves at 0.7x. Reduce Motion: opacity only. The animation sits on the popover's own container, so the caller's trigger never inherits it.
- A click outside closes it (animated); Escape closes it without animation. Both come from a local event monitor rather than `onExitCommand`, because a click on a button does not always move keyboard focus, and Escape must work wherever focus is. A key-press open is the caller's `withoutAnimation`.
- Only the presented popover is modal to VoiceOver, and focus moves into it. The bare `GlassPopover` view is not: the trait hides everything else on screen, which the first Gallery page showed by hiding its own other sections.
- Open: `skill-mapping.md` says "materialise, don't fade" (`glassEffectTransition(.materialize)`). This popover, the toast and the drop-zone plate use scale plus opacity instead, which is what both reviews flagged as the one remaining disagreement. It wants judging at 0.1x over the busy backdrop by a person before either the code or the mapping changes; a re-open during the 0.13 s exit also briefly shows two panels.

### Toast and UndoToast
- One glass capsule, 40 pt tall, above the bottom edge. The undo button is tinted text, not a second glass surface. Dismiss is a full 40 pt square at the end cap, its glyph concentric with the cap. A leading symbol sits 2 pt closer to the edge than text would.
- Rises 12 pt from `Motion.enterScale`, anchored at the bottom, with opacity, over `Duration.panel`; never its full height. Leaves at 0.7x. The animation is scoped to the toast's own container: a host that changes in the same transaction (a grid reflowing after a delete) never inherits it.
- A second toast replaces the first in place (`ToastPresenter`, tested): the capsule keeps its identity and the text crossfades, so rapid actions cannot stack. State-driven transitions only. Accepted: a new toast inside the 0.18 s exit of the last one briefly overlaps it.
- Lifetime 5 s, held while the pointer or VoiceOver focus is on it, so it never goes from under the user. Command-Z undoes without animation, and only an undo toast takes it: a plain toast leaves the app's own Undo alone. New messages are announced to VoiceOver.

### HotkeyRecorder
- Ships unassigned. `HotkeyRecorderState` (tested) owns the behaviour: a combination needs Command, Control or Option (Shift alone would swallow typing) unless it is a function key; a conflict is shown and recording continues; Escape cancels, Delete clears.
- No animation anywhere: every change is a key press.
- While recording, a local event monitor takes key presses so Command-W and the like are recorded, not obeyed. A click elsewhere or the window losing key status cancels.
- The caption line is always present, so rows below never jump when the hint or the conflict appears. A conflict is a red symbol plus words, and is announced.

### SidebarRow
- Not glass; it sits on the sidebar's glass. Selected is an accent fill at 18% (32% under Increase Contrast) in `Radius.control`; hover is `.quinary`, faded over `Duration.hover` in and 0.7x out.
- No part of the row animates with the selection, symbol included: arrow keys move it, and a caller's `withAnimation` must not leak in.
- `SidebarRowGroup` is the keyboard path: one tab stop, like a native list, where up and down move the selection inside `withoutAnimation`.
- Outline symbol by default, `.fill` plus accent when selected, in a fixed 20 pt slot so titles line up. Badge digits are monospaced.
- Hit area 40 pt tall; the visible fill is inset 2 pt top and bottom so stacked rows' targets meet without overlapping. Stack rows with spacing 0. The focus ring follows the fill.
- `PressButtonStyle(isStatic: true)`: a full-width row that shrinks on every click distracts, so it dims instead.

### FitModePicker
- One glass capsule (`inspectorControl`); the selection pill is a plain `primary` fill at 14% (30% under Increase Contrast), so no glass on glass. Capsule in capsule with a 4 pt inset is concentric by construction.
- The pill moves by `offset` only, with `Spring.ui`, scoped to the pill. A first selection appears in place: the pill has nowhere to slide from. Arrow keys go through `withoutAnimation`, clamp at the ends, and the control is one tab stop like a native segmented control.
- Reduce Motion: the sliding pill is replaced by per-segment pills that crossfade.
- Segments are equal width (a private `Layout`), 32 pt drawn in a 40 pt hit area. Selected text is `primary`, the rest `secondary`, so colour marks selection as well as the pill.
- Generic over its value: "fit mode" is a term of `CONTEXT.md`, so the package takes options, not the app's enum.

### VolumeSlider
- Native `Slider`, labelled "Volume" with a percent value. The speaker symbol shows the level in thirds and swaps with `.symbolEffect(.replace)`, in a fixed 24 pt leading-aligned slot so the speaker body stays still as waves come and go.
- The readout takes its width from a hidden "100%", monospaced, so nothing shifts at any text size.
- Only a click on the mute button animates the symbol. Waves changing under a dragged slider, and a mute from the keyboard, swap at once.
- Muted dims the slider to 45% without animation; moving the slider unmutes. VoiceOver reads "Muted, 60%", since the dimming is visual only.

### SetOnDisplayButton
- `.controlSize(.extraLarge)`: it is the inspector's one primary action, and its chevron sits 2 pt away, where a missed click would set the wrong display. A long display name truncates; the chevron keeps its size.
- One target: a `glassProminent` button. Several: the same button for the first target plus a separate chevron `Menu` listing every target and "All Displays", both in one `GlassEffectContainer`. A native split `Menu(primaryAction:)` was tried first and rejected: on macOS it drops the glass style and cannot show the spinner. The chevron menu still renders as plain glass rather than prominent; it reads as the secondary half.
- The icon slot is a fixed 16 pt square, so the title never moves. Idle to done is a symbol replace (`display` to `checkmark`); the spinner crossfades over `Duration.hover`.
- `.working` disables the control. `.done` stays enabled; the caller returns it to idle.
- Takes names and string identifiers, never the app's display type.

### DetailsList
- A two-column `Grid` on the first text baseline: labels trailing and `secondary`, values selectable, monospaced digits, two lines at most with middle truncation so a path keeps both ends.
- No surface of its own; it lives in the inspector. VoiceOver reads each row as "label, value".

### DisplayNowPlayingCard
- Lives inside a glass popover, so it is a `quaternary` fill at 60%, not glass. `Radius.card` as the `containerShape`, with a `ConcentricRectangle` thumbnail 8 pt in: 16 - 8 = 8 pt, concentric.
- Thumbnail 64 x 40 (16:10): 40 pt high so the card is one row tall beside a `TransportCluster`.
- Not playing: the poster drops to 30% saturation and 70% opacity with `Spring.ui`; the status line is the static cue, so colour is never the only signal.
- The status line is always laid out, so the card keeps its height when a status comes and goes: pressing Pause must not move the button under the pointer.
- All three text lines truncate; the accessory keeps its size.

### TransportCluster
- Three icon buttons with 40 pt circular hit areas and `.press`. Play/pause is `.title3`, skips are body size, so the primary action reads first.
- The play triangle sits 1 pt right of centre (optical centring); pause sits at 0. The swap is `.symbolEffect(.replace)`.
- `.glass` puts all three in one capsule, never three glass circles. `.plain` is for inside a card or popover.
- `canSkip: false` dims and disables the skips in place, so the cluster never changes width.

### PlaylistPicker
- A native `Menu` with the glass button style: checkmarks, keyboard and VoiceOver come free. Counts use the native menu badge.
- "No Playlist" is the first item, the only way back to `nil`; then a divider and "New Playlist…". An empty list shows only the latter.
- No custom motion.

### RecentsStrip
- Thumbnails 72 x 45, `Radius.control`, outlined, `.press`. Title is the tooltip and the VoiceOver label.
- The first items the strip is given stagger in, even if they load after the strip appears: opacity, 8 pt rise and `Motion.enterScale`, over `Duration.panel`, delayed by `Stagger` (40 ms, capped at 8). Items inserted later enter alone while their neighbours make room with `Spring.move`; the strip never replays. Reduce Motion: opacity only, together.
- `entrance: .none` is for a strip revealed by a key press or shown often (the menu-bar popover): an `onAppear` entrance starts its own transaction, so a caller's `withoutAnimation` could never have reached it.
- The stack is not lazy on purpose: a lazy stack would replay entrances while scrolling.

### DropZoneOverlay
- Scrim (black 30%, 50% under Increase Contrast) and a dashed accent border fade only; the central glass plate enters from `Motion.enterScale` with opacity over `Duration.popover` and leaves at 0.7x. Centre anchor, because it has no trigger to grow from.
- The border is state, hence a border, in accent so it reads over light windows too.
- The symbol is semibold, to carry the weight of the title beneath it.
- Never takes hits: the drop must reach the view underneath. Becoming targeted is announced, since a drag moves no focus.

### ImportProgressRow
- Every state has the same height and columns. The native progress bar and caption are always laid out; on failure they go transparent and the message takes their place, so no frame animates.
- The percent slot is sized by a hidden "100%", monospaced and trailing.
- The trailing slot is one symbol in one button in every state (`xmark.circle.fill`, `arrow.clockwise.circle.fill`, `checkmark.circle.fill`: one variant, so the replace does not jump in weight); when finished it is disabled and hidden from VoiceOver.
- The bar gives way to the failure message as one crossfade (`Duration.menu`), in step with the trailing symbol.
- Rejected: pulling the 40 pt trailing slot out past the row's edge to align the glyph optically. The row's layout bounds stay honest, and its target never overlaps a neighbour's.
- Failure is a symbol plus words in red, never red alone. Titles truncate in the middle because file names differ at the end.

### EmptyState
- Content layer, so no glass: `.borderedProminent` primary, link-style secondary with its own 40 pt target (the stack has no spacing, so the two targets meet and never overlap).
- No entrance animation: it appears on navigation, which is frequent.
- Text column capped at 320 pt and centred, the nearest SwiftUI gets to balanced wrapping.

### OnboardingCard
- Opaque card, `Radius.panel`, two-layer shadow for elevation (no border, except under Increase Contrast). The illustration is 8 pt in and clipped with `ConcentricRectangle`: 20 - 8 = 12 pt.
- The one use of the 0.10 s group stagger: illustration, text, then buttons enter with opacity, an 8 pt rise and a 4 pt blur over `Duration.sheet`. Once per appearance, never on hover or a key press. Reduce Motion: opacity only, together.
- Moving between steps keeps the card's identity. By click, the picture, the words and the dots crossfade over `Duration.menu` and the height, if it changes, snaps; by Return nothing animates. The card tells the two apart itself (`withoutAnimationIfKeyPress`), because both arrive through the same closure and no caller could.
- In dark mode a pure-white ring at 8% keeps the card's edge, where black shadows vanish.
- Page dots are one VoiceOver element, "Step 2 of 4".

### LoginItemRow
- Told its state (off, on, needs approval, not found); never asks `SMAppService`. The switch's binding reads the given state and its setter only calls `onChange`, so the switch can never disagree with System Settings.
- No animation at all: the state changes rarely and from outside, and a caption fading in would mean animating the row's height.
- Warnings are a symbol plus words, and are announced, since they appear while focus stays on the switch. VoiceOver reads "On, needs approval in System Settings", not a bare "on". Takes the app's name as a parameter.
- Callers should hand the new state back in the same turn as `onChange`: a switch answered late slides on, back, and on again.

### PauseRuleToggle
- A native switch whose label is the whole row, so the words are clickable and VoiceOver reads "title, detail, switch, on".
- Symbols sit in a fixed 24 pt slot so titles line up across rows. Every row is at least 40 pt, with or without a detail line.
- A click on the words animates the thumb (`Spring.ui`), as a click on the switch does.
- An unavailable rule shows off and disabled without changing the stored value, so the preference survives a move to another Mac.

### StatusLine
- The one place a wallpaper service that has stopped responding is reported: a static warning symbol, the words, and Restart. No pulse.
- Only a change of kind crossfades (opacity, `Duration.hover`, one scoped animation that a caller's `withoutAnimation` still silences); text inside `.working` swaps in place, because a count can change many times a second.
- Always 40 pt tall, so the window never shifts when Restart appears, and Restart's hit area fills that height. Restart never truncates; the message gives way instead. Becoming degraded is announced to VoiceOver.
