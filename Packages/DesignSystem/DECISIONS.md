# Design system decisions

The values chosen for each token and component, and why. The rules they answer to are in `docs/design/skill-mapping.md`; the skills are in `.agents/skills/`. Add to an entry when a value changes; do not rewrite history.

Every component reads accessibility through `@Accessibility`, never the system environment values, so the Gallery can override them for one page. Two resolvers build every animation, and both apply the Gallery's slow motion:

- `accessibility.animation(_:)` is for movement. Under Reduce Motion it becomes the 0.2 s crossfade, and the component also drops the movement itself (opacity-only transition, no throw, no stagger).
- `accessibility.fade(_:)` is for changes of opacity or colour only. Reduce Motion leaves it alone: reduced motion keeps fades and drops movement. Without this split a 0.12 s hover wash became 0.2 s under Reduce Motion, and exits stopped being quicker than enters.

`accessibility.symbolReplace` is the symbol-replace content transition, or a plain fade under Reduce Motion (the system honours only the real setting, not the Gallery's override).

The overrides-over-system rule lives in one place (M6): `AccessibilitySettings(overrides:systemReduceMotion:systemReduceTransparency:systemIncreaseContrast:)`, table-tested. `@Accessibility` gives it the environment's values; `AccessibilitySettings.system(overriding:)` gives it `NSWorkspace`'s, for AppKit code that starts a change the design system animates before any view has read `@Accessibility` (the menu-bar popover's first open). The app had written the rule out again against `NSWorkspace`; now it reads no accessibility setting itself.

Changes made from a key press run inside `withoutAnimation`, which also switches off a component's own `.animation(_:value:)`. Where one control answers both a click and a key press (a default button, a focused button pressed with Space), `withoutAnimationIfKeyPress` decides from the current event, so the rule does not rest on the caller.

Every `.animation(_:value:)` sits on the one effect it drives, never on a container that also holds the caller's content. Hover fades run `Motion.enter` in and `Motion.exit` out. Focus rings follow the control's drawn shape (`contentShape(.focusEffect, …)`), not its 40 pt hit rectangle. A focusable container's ring is the union of the focus shapes of everything inside it, so a container that is one tab stop (`SidebarRowGroup`) keeps its focusable view beside its rows, not around them.

VoiceOver on macOS speaks an element's value before its label ("3, Playlists, button"; "42%, Optimising, Harbour at Dusk.mov"), heard on 2026-09-22 with VoiceOver driven by script over every Gallery page. That order is right for a control whose value changes under the user (a slider, the focal point, the hotkey field, a menu button) and wrong for a row that is information, so rows fold their words into one label in reading order and set no value: `SidebarRow` ("Playlists, 3"), `DetailsList` ("Resolution, 3840 × 2160"), `DisplayNowPlayingCard` ("Built-in Display, Harbour at Dusk, Paused: on battery"), `ImportProgressRow` ("Harbour at Dusk.mov, 42%, Optimising") and the `DropZoneOverlay` plate ("Drop to Import. Videos and Live Photos…"). A native switch reads label first, so `LoginItemRow` and `PauseRuleToggle` need nothing.

Reviewed on 2026-09-21 with `review-animations` and `make-interfaces-feel-better` (full mode); the findings are folded into the entries below. Looked at again on 2026-09-22: every page walked with VoiceOver (scripted, transcripts kept out of the repo), tabbed through with keyboard navigation on, and the motion recorded at 0.1x over the busy backdrop; what changed as a result is in the entries. Both skills were then re-run over all 22 components (2026-09-22): review-animations approved 21 and blocked OnboardingCard (the step crossfade sat on the card, so a height change animated; fixed below); make-interfaces-feel-better approved 9, blocked RecentsStrip (the strip did not clip; fixed below) and asked for changes on the rest, all applied or recorded under the component. A focused button pressed with Space was checked at 0.1x: the change lands in one frame, so `withoutAnimationIfKeyPress` reading `.keyDown` is right.

Where a component's own action can arrive from a focused button (Space or Return), the component wraps it in `withoutAnimationIfKeyPress` itself: TransportCluster, RecentsStrip, ImportProgressRow, StatusLine's Restart and PanZoomEditor's Reset, as OnboardingCard and VolumeSlider already did. M6 found three that did not and left the rule to their callers: SetOnDisplayButton (the button and each menu item), EmptyState (both actions) and Toast (Undo and Dismiss; Command-Z already ran without animation) now decide it themselves too, as do M6's LabelButton, LabelToggle, SymbolButton and FavouriteToggle. `CompactTextButton` is the shared small text button (Restart, Reset): a compact capsule with the full 40 pt target, that rule built in. It is public since M6, for the popover's Choose on a card whose display shows nothing: the same secondary action in a line of controls, which a native bordered button would have given a target under 40 pt.

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
- Increase Contrast raises it to 35%, same colour. The skills give no number; 35% is roughly three times the standard strength.
- Judged on 2026-09-22 against four stock desktop pictures on the WallpaperTile page (a light sky, a near-black night shot, grey cloud, a near-white metallic render), light and dark, contrast on and off. At 10% the near-white picture on the light window and the night picture on the dark window keep an edge only just; at 35% both have a thin definite edge that still reads as the picture's own and not as a frame. 35% stays.
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
- The poster goes live after a 200 ms dwell, decided by `HoverDwell` (tested), and `LivePreviewCoordinator` shares one dwell across the grid so two tiles are never live. The preview crossfades in place over `Duration.panel` and leaves at 0.7x; the animation is scoped to the preview alone, so a grid reflow in the same update cannot animate a tile's frame. The caller supplies the preview as a view, so the package never touches AVFoundation. The Gallery holds one tile live by giving it its own coordinator and telling it the pointer arrived; no API was added for that.
- The caller's preview is clear until it has a picture (M6): the app's player had a black background, which faded in with the crossfade before the first frame was up and darkened the whole tile mid-fade (recorded at 0.1x). The tile's preview now passes a clear background, so the poster shows through until the frame comes.
- VoiceOver reads a favourite as "Favourite, Paper Lanterns, button" and the selected tile with the selected trait. The tile's element is made with `accessibilityElement(children: .ignore)` for that label, which is not the button's element and has no press, so it carries the button's action as its own `accessibilityAction`: without it VoiceOver's VO-Space, and any Accessibility press, did nothing.
- Reduce Motion disables hover autoplay entirely (`livePreviewScope` switches the coordinator off).
- No hover scale: a grid of tiles is swept constantly, and movement on every pass would be noise.
- The title colour and the selection ring carry `.animation(nil, value: isSelected)`, so a caller's `withAnimation` (a selection change that also scrolls) cannot fade them; the same promise SidebarRow makes.
- Press is 0.96 like every other control. The focus ring follows the poster, not the title: a 16:10 rounded rectangle at the top of the label, set on the label itself, because a focus shape set on the picture inside the label is not the button's and the ring fell around poster and title together.

### FocalPointEditor
- The value is a `UnitPoint`, 0 to 1 on each axis; the maths (`FocalPointMath`, tested) converts to and from the letterboxed picture and clamps to it.
- The handle follows the pointer inside `withoutAnimation`. On release, above 300 pt/s the handle carries on a quarter of the way to SwiftUI's projected end with `Spring.momentum(initialVelocity:)`, starting at the pointer's speed; below it, nothing animates. A quarter, because a full throw sends a precise control flying. Under Reduce Motion there is no throw: the handle stays where it was let go.
- Cross-hairs are there at once on pointer down and fade out on release (`Motion.exit(Duration.hover)`). They are white over a wider dark stroke, as the handle has its shadow, so they hold over any picture. The handle is 24 pt drawn, 40 pt hit area.
- The cross-hairs are two positioned strokes, not a `Canvas`: a `Canvas` does not interpolate, so on a flick they jumped to the landing point while the handle was still springing there. Now they carry the release spring too and travel with the handle as they fade; during the drag itself they move without animation.
- Arrow keys nudge by 0.01 without animation. VoiceOver: adjustable left/right in steps of 0.05, with "Move up" and "Move down" actions.

### PanZoomEditor
- Pan is a fraction of the frame and zoom a factor from 1 to 4, matching how the app stores a presentation. `PanZoomMath` (tested) clamps both so the picture always covers the frame, with the same focal-point rule as the core's `pictureRect`.
- The picture is laid out once at zoom 1 and then moved with `scaleEffect` and `offset` only, so nothing animates a frame.
- Dragging past an edge rubber-bands, up to 60 pt; pinching past 1x or 4x gives by up to 0.25 in the same way. Release: with velocity, `Spring.momentum(initialVelocity:)` and a quarter of the projected throw; at rest but overscrolled, `Spring.ui` (no bounce, because nothing was moving).
- Picking the picture up mid-throw continues from where it is on screen: an `Animatable` modifier reports the in-flight pan and overscroll, and `unrubberband` turns the overscroll back into a drag. Repeated flicks are how a zoomed picture is crossed, so this path is the normal one.
- Reduce Motion: no throw, a plain stop at the edges with nothing to spring back, and Reset jumps.
- Reset by click animates with `Spring.move` (0.4 s: the token for an element changing position; a spring's duration is where it settles, and most of the travel is over well inside 300 ms). By Space or Return it does not animate. Arrow keys pan by 0.02 and + / - zoom by 0.1, without animation.
- Reset is a `CompactTextButton`, the same control as StatusLine's Restart: it was a default push button, the one control in a row of 40 pt targets without one.
- The zoom slider pulls pan back as it zooms out, so what VoiceOver reads is what is on screen.

### GlassPopover
- Glass, `Radius.panel`, and a `containerShape` so children can be concentric. `contentPadding` is 12 pt by default, and 4 pt for cards of `Radius.card` (20 = 16 + 4). Content inside must not be glass.
- Enters from `Motion.enterScale` with opacity, anchored at the edge that touches the trigger, over `Duration.popover` (0.18 s); leaves at 0.7x. Reduce Motion: opacity only. The animation sits on the popover's own container, so the caller's trigger never inherits it.
- A click outside closes it (animated); Escape closes it without animation. Both come from a local event monitor rather than `onExitCommand`, because a click on a button does not always move keyboard focus, and Escape must work wherever focus is. A key-press open is the caller's `withoutAnimation`.
- Only the presented popover is modal to VoiceOver, and focus moves into it. The bare `GlassPopover` view is not: the trait hides everything else on screen, which the first Gallery page showed by hiding its own other sections.
- Open: `skill-mapping.md` says "materialise, don't fade" (`glassEffectTransition(.materialize)`). This popover, the toast and the drop-zone plate use scale plus opacity instead, which is what both reviews flagged as the one remaining disagreement. It wants judging at 0.1x over the busy backdrop by a person before either the code or the mapping changes; a re-open during the 0.13 s exit also briefly shows two panels.
- Judged on 2026-09-22 from 0.1x recordings over the busy backdrop, both ways built and filmed (the materialise build was `glassEffectTransition(.materialize)` inside a `GlassEffectContainer` for all three). Decision: scale plus opacity stays. Materialise brings the panel in as a blur that sharpens, so the words are a smear at the moment the user reads them; it grows from the centre, not the trigger; its duration is the system's, so `Duration.popover`, the 0.7x exit and the Gallery's 0.1x do not reach it; and in that build the exit was a hard cut. It suits a glass control that appears beside other glass in one container (a toolbar button, a split button's second half), which is what the mapping row now says. The materialise build was not kept.

### Toast and UndoToast
- One glass capsule, 40 pt tall, above the bottom edge. The undo button is tinted text, not a second glass surface. Dismiss is a full 40 pt square at the end cap, its glyph concentric with the cap; its focus ring is the cap's circle and Undo's a capsule, since square rings inside a capsule looked bolted on (seen in the keyboard pass). A leading symbol sits 2 pt closer to the edge than text would.
- Rises 12 pt from `Motion.enterScale`, anchored at the bottom, with opacity, over `Duration.panel`; never its full height. Leaves at 0.7x. The animation is scoped to the toast's own container: a host that changes in the same transaction (a grid reflowing after a delete) never inherits it.
- A second toast replaces the first in place (`ToastPresenter`, tested): the capsule keeps its identity and the text crossfades, so rapid actions cannot stack. State-driven transitions only. Accepted: a new toast inside the 0.18 s exit of the last one briefly overlaps it.
- Lifetime 5 s, held while the pointer or VoiceOver focus is on it, so it never goes from under the user. Command-Z undoes without animation, and only an undo toast takes it: a plain toast leaves the app's own Undo alone. New messages are announced to VoiceOver.

### HotkeyRecorder
- Ships unassigned. `HotkeyRecorderState` (tested) owns the behaviour: a combination needs Command, Control or Option (Shift alone would swallow typing) unless it is a function key; a conflict is shown and recording continues; Escape cancels, Delete clears.
- The state and the view take a starting `phase`, so the Gallery can hold a recorder in the recording and conflict phases for looking at. One started that way is a picture: it listens only once clicked.
- VoiceOver reads the field as "None, Next wallpaper, button" or "⌃⌥P, Pause or resume, button": value first, as for a text field, which is what it is.
- No animation anywhere: every change is a key press.
- While recording, a local event monitor takes key presses so Command-W and the like are recorded, not obeyed. A click elsewhere or the window losing key status cancels.
- The caption line is always present, so rows below never jump when the hint or the conflict appears. A conflict is a red symbol plus words, and is announced.
- The recorder is as wide as its field and the clear button's slot in every phase: a caption that fits starts under the field, and a wider one, usually a conflict, hangs from the field's trailing edge and runs out under the row's label (`HotkeyRecorderCaption`, tested). A caption that widened the recorder moved the field 60 pt left in Settings' trailing-aligned rows on the key press that made the conflict. A host sets the recorder at a row's trailing edge, as a form does.
- The clear button's 40 pt slot is always laid out too, faded out and disabled when there is nothing to clear: inserting it moved the field by 44 pt on the very click that started recording, and rows in a trailing-aligned form did not line up.

### SidebarRow
- Not glass; it sits on the sidebar's glass. Selected is an accent fill at 18% (32% under Increase Contrast) in `Radius.control`; hover is `.quinary`, faded over `Duration.hover` in and 0.7x out.
- No part of the row animates with the selection, symbol included: arrow keys move it, and a caller's `withAnimation` must not leak in.
- `SidebarRowGroup` is the keyboard path: one tab stop, like a native list, where up and down move the selection inside `withoutAnimation`. The focusable view sits behind the rows (`background`), not around them: as their ancestor its focus ring was the union of every row's ring shape, five rings at once. Behind them it is one `Radius.control` ring around the group. VoiceOver reads it as "Library, group" with four buttons inside, the selected one with the selected trait.
- The badge is part of the label ("Playlists, 3"), not a value, which VoiceOver would read first. The row's element is made with `accessibilityElement(children: .ignore)` for that label, which is not the button's element and has no press, so it carries the button's action as its own `accessibilityAction`: without it VoiceOver's VO-Space, and any Accessibility press, did nothing.
- Outline symbol by default, `.fill` plus accent when selected, in a fixed 20 pt slot so titles line up. Badge digits are monospaced.
- Hit area 40 pt tall; the visible fill is inset 2 pt top and bottom so stacked rows' targets meet without overlapping. Stack rows with spacing 0. The focus ring follows the fill.
- `PressButtonStyle(isStatic: true)`: a full-width row that shrinks on every click distracts, so it dims instead.
- `SidebarRowGroup` takes a context menu per row (M6: the library's playlist rows, Rename… and Delete), set on each row rather than on the group, so a secondary click acts on the row under the pointer and not on the selected one. A group without one is the `EmptyView` case and shows no menu.

### FitModePicker
- One glass capsule (`inspectorControl`); the selection pill is a plain `primary` fill at 14% (30% under Increase Contrast), so no glass on glass. Capsule in capsule with a 4 pt inset is concentric by construction.
- The pill moves by `offset` only, with `Spring.ui`, scoped to the pill. A first selection appears in place: the pill has nowhere to slide from. Arrow keys go through `withoutAnimation`, clamp at the ends, and the control is one tab stop like a native segmented control.
- The labels' colour changes over the same `Spring.ui`, so the words and the pill arrive together; it used to snap on the click while the pill was still on its way.
- Reduce Motion: the sliding pill is replaced by per-segment pills that crossfade.
- Segments are equal width (a private `Layout`), 32 pt drawn in a 40 pt hit area. Selected text is `primary`, the rest `secondary`, so colour marks selection as well as the pill.
- Generic over its value: "fit mode" is a term of `CONTEXT.md`, so the package takes options, not the app's enum.
- The pill's fill is `Pill` (M6), which LabelToggle's on state also reads, so the 14% and 30% live in one place.

### VolumeSlider
- Native `Slider`, labelled "Volume" with a percent value. The speaker symbol shows the level in thirds and swaps with `.symbolEffect(.replace)`, in a fixed 24 pt leading-aligned slot so the speaker body stays still as waves come and go.
- The readout takes its width from a hidden "100%", monospaced, so nothing shifts at any text size.
- Only a click on the mute button animates the symbol. Waves changing under a dragged slider, and a mute from the keyboard, swap at once.
- Muted dims the slider to 45% without animation; moving the slider unmutes. VoiceOver reads "Muted, 60%", since the dimming is visual only. Read from the installed app's accessibility tree on 2026-09-24: the card's slider is named "Volume" (its attributed description, which `.labelsHidden()` keeps) and valued "Muted, 0%". An explicit `accessibilityLabel` on top of it read "Volume, Volume", so there is none.
- The click's `withAnimation` (for the symbol replace) reached the slider's opacity and the readout's colour too: at 0.1x the slider faded to 45% over the spring. Both now carry `.animation(nil, value: isMuted)`, so only the symbol animates. Seen in the 0.1x recording on 2026-09-22; static review had missed it.
- `speaker: .indicator` (2026-09-24, for the popover's cards): the speaker shows the level and is not a control, for where the one mute is elsewhere. The popover's footer holds Mute for every display; a mute in each card would repeat it, and a click there would silence every display from inside one display's card, which reads as that display's own. So the card's speaker is `secondary`, as the readout is, with no target and no tab stop, and is hidden from VoiceOver: the slider already says "Volume", "60%" or "Muted, 60%". It still takes the slash while muted, the static cue beside the 45% dimming, and swaps at once, since mute reaches it from the footer, by a click that does not animate or by a key. Moving the slider unmutes, as the mute button's variant does.
- One symbol rule for both speakers, `VolumeSymbol` (table-tested): thirds, the slash while muted. The row is at least 40 pt tall in both, so the slider sits at the same height beside a button or a bare symbol.
- The slider's own target is AppKit's, 16 pt tall, in both variants: the accessibility frames read 318 x 16 in the popover and 198 x 16 on the Gallery page, and a frame given to the slider, `maxHeight: .infinity` included, did not grow it (built and measured on 2026-09-24). As with PlaylistPicker's menu button, the target is the native control's; the 40 pt row keeps 12 pt clear above and below it, so no other target comes near it.

### SetOnDisplayButton
- `.controlSize(.extraLarge)`: it is the inspector's one primary action, and its chevron sits 2 pt away, where a missed click would set the wrong display. A long display name truncates; the chevron keeps its size.
- One target: a `glassProminent` button. Several: the same button for the first target plus a separate chevron `Menu` listing every target and "All Displays", both in one `GlassEffectContainer`. A native split `Menu(primaryAction:)` was tried first and rejected: on macOS it drops the glass style and cannot show the spinner. The chevron menu still renders as plain glass rather than prominent; it reads as the secondary half.
- The icon slot is a fixed 16 pt square, so the title never moves. Idle to done is a symbol replace (`display` to `checkmark`); the spinner crossfades over `Duration.hover`.
- `.working` disables the control. `.done` stays enabled; the caller returns it to idle.
- Takes names and string identifiers, never the app's display type.

### DetailsList
- A two-column `Grid` on the first text baseline: labels trailing and `secondary`, values selectable, monospaced digits, two lines at most with middle truncation so a path keeps both ends.
- No surface of its own; it lives in the inspector. VoiceOver reads each row as one label, "Resolution, 3840 × 2160"; set as a value the number came first.

### DisplayNowPlayingCard
- Lives inside a glass popover, so it is a `quaternary` fill at 60%, not glass. `Radius.card` as the `containerShape`, with a `ConcentricRectangle` thumbnail 8 pt in: 16 - 8 = 8 pt, concentric.
- Thumbnail 64 x 40 (16:10): 40 pt high so the card is one row tall beside a `TransportCluster`.
- Not playing: the poster drops to 30% saturation and 70% opacity with `Spring.ui`; the status line is the static cue, so colour is never the only signal.
- The status line is always laid out, so the card keeps its height when a status comes and goes: pressing Pause must not move the button under the pointer. Its opacity fades over the same `Spring.ui` as the poster muting beside it.
- All three text lines truncate; the accessory keeps its size.
- In the popover (M6) the accessory is two rows, the transport and the playlist picker under it, so a card showing a wallpaper is 20 pt taller than one row; the thumbnail and the words stay centred beside it. A card whose display shows nothing has `CompactTextButton`'s Choose, one row.
- `footer:` (2026-09-24) is a row as wide as the card under the thumbnail, the words and the accessory: in the popover, the display's volume, a `VolumeSlider` whose speaker shows the level (`.indicator`), the user's choice of layout. It sits straight under the row with no gap, since its 40 pt brings its own room, and inside the card's 8 pt padding: the speaker lines up with the thumbnail's leading edge, and the readout ends at the card's content edge, where Choose ends in a card below. A card showing a wallpaper is then 40 pt taller (116 pt in the popover), with 8 pt of padding and a 40 pt row at each end: the knob sits 20 pt above the card's bottom edge as the transport's glyphs sit about 20 pt below its top (measured in the popover's capture). A footer that draws nothing takes no room, so a card whose display shows nothing stays one row. Pausing leaves the footer alone: the card keeps its height, and the volume is the wallpaper's, not the playback's.

### TransportCluster
- Three icon buttons with 40 pt circular hit areas and `.press`. Play/pause is `.title3`, skips are body size, so the primary action reads first.
- The play triangle sits 1 pt right of centre (optical centring); pause sits at 0. The swap is `.symbolEffect(.replace)`.
- `.glass` puts all three in one capsule, never three glass circles. `.plain` is for inside a card or popover.
- `canSkip: false` dims and disables the skips in place, so the cluster never changes width.

### PlaylistPicker
- A native `Menu` with the glass button style: checkmarks, keyboard and VoiceOver come free. Counts use the native menu badge.
- "No Playlist" is the first item, the only way back to `nil`; then a divider and "New Playlist…". An empty list shows only the latter.
- No custom motion.
- `style: .plain` (M6) is a borderless menu button, for inside a card or the popover: the glass button there was glass on glass, which the popover forbids. `.glass` stays the default, for the inspector. Like `TransportClusterStyle`, the caller says where it sits.
- In the popover it sits under the card's `TransportCluster` at `.controlSize(.small)`, naming the playlist. Tried first beside the transport with its symbol only (`.labelStyle(.iconOnly)`): it left the card's words about 115 pt of a 400 pt popover, and nothing on screen said which playlist a display was on. Its target is the native menu button's, shorter than 40 pt: a SwiftUI `Menu` on macOS draws its label as an AppKit pop-up button, which ignores a frame or content shape given to the label.
- The symbol is an `NSImage` described as "Playlist" (M6). The popover's accessibility tree showed a menu button titled "Playlist", valued "Evening" and described as "Stack of rectangles": the pop-up button AppKit draws the label with takes its description from its image, and a symbol's own description is its shape. Both styles share the label, so both had it. VoiceOver should read "Evening, Playlist, menu button"; not yet walked with VoiceOver.

### RecentsStrip
- Thumbnails 72 x 45, `Radius.control`, outlined, `.press`. Title is the tooltip and the VoiceOver label.
- The scroll view clips. It had `scrollClipDisabled` so the focus ring and the 8 pt rise were not cut off, and with the clip off a strip with more items than fit drew every one of them across the page (seen in the light-mode captures: fourteen posters to the window's edge, and a scroller saying otherwise). The room the ring and the rise need is now content margins inside the clip, taken back outside with negative padding, so the layout is unchanged.
- A removed item leaves with an explicit opacity exit at 0.7x; entering is the thumbnail's own affair (`.identity` insertion), so a later insertion no longer fades twice.
- The first items the strip is given stagger in, even if they load after the strip appears: opacity, 8 pt rise and `Motion.enterScale`, over `Duration.panel`, delayed by `Stagger` (40 ms, capped at 8). Items inserted later enter alone while their neighbours make room with `Spring.move`; the strip never replays. Reduce Motion: opacity only, together.
- `entrance: .none` is for a strip revealed by a key press or shown often (the menu-bar popover): an `onAppear` entrance starts its own transaction, so a caller's `withoutAnimation` could never have reached it.
- The stack is not lazy on purpose: a lazy stack would replay entrances while scrolling.

### DropZoneOverlay
- Scrim (black 30%, 50% under Increase Contrast) and a dashed accent border fade only; the central glass plate enters from `Motion.enterScale` with opacity over `Duration.popover` and leaves at 0.7x. Centre anchor, because it has no trigger to grow from. The plate carries the popover's shadow: one floating layer, one elevation.
- The border is state, hence a border, in accent so it reads over light windows too.
- The symbol is semibold, to carry the weight of the title beneath it.
- Never takes hits: the drop must reach the view underneath. Becoming targeted is announced, since a drag moves no focus.

### ImportProgressRow
- Every state has the same height and columns. The native progress bar and caption are always laid out; on failure they go transparent and the message takes their place, so no frame animates.
- The percent slot is sized by a hidden "100%", monospaced and trailing.
- The trailing slot is one symbol in one button in every state (`xmark.circle.fill`, `arrow.clockwise.circle.fill`, `checkmark.circle.fill`: one variant, so the replace does not jump in weight); when finished it is disabled and hidden from VoiceOver. Its focus ring is a circle, like the glyph; the target stays the 40 pt square.
- The bar gives way to the failure message as one crossfade (`Duration.menu`), in step with the trailing symbol.
- Rejected: pulling the 40 pt trailing slot out past the row's edge to align the glyph optically. The row's layout bounds stay honest, and its target never overlaps a neighbour's.
- Failure is a symbol plus words in red, never red alone. Titles truncate in the middle because file names differ at the end.
- The bar is a new one whenever it switches between knowing its length and not (M6). Changed in place, AppKit's indeterminate sweep ran on for about two seconds into Finished: seen when an import that was still at its fingerprint (no fraction) found its file already in the library, which M6's duplicate-at-once flow shows on every drop of a file the library has.

### EmptyState
- Content layer, so no glass: `.borderedProminent` primary, link-style secondary with its own 40 pt target (the stack has no spacing, so the two targets meet and never overlap).
- No entrance animation: it appears on navigation, which is frequent.
- Text column capped at 320 pt and centred, the nearest SwiftUI gets to balanced wrapping.

### OnboardingCard
- Opaque card, `Radius.panel`, two-layer shadow for elevation (no border, except under Increase Contrast). The illustration is 8 pt in and clipped with `ConcentricRectangle`: 20 - 8 = 12 pt.
- The one use of the 0.10 s group stagger: illustration, text, then buttons enter with opacity, an 8 pt rise and a 4 pt blur over `Duration.sheet`. Once per appearance, never on hover or a key press. Reduce Motion: opacity only, together.
- Moving between steps keeps the card's identity. By click, the picture, the words and the dots crossfade over `Duration.menu` and the height, if it changes, snaps; by Return nothing animates. The card tells the two apart itself (`withoutAnimationIfKeyPress`), because both arrive through the same closure and no caller could.
- The crossfade is three scoped animations, one each on the picture, the words and the dots, and none on the card: on the card it animated the height too when a step's text wrapped differently. The Gallery had hidden this by wrapping its click handlers in `withoutAnimation`; it no longer does.
- In dark mode a pure-white ring at 8% keeps the card's edge, where black shadows vanish.
- Page dots are one VoiceOver element, "Step 2 of 4".
- An accessory (M7): controls of a step's own, under the words and entering with them in the text group. Onboarding's first card offers the bundled samples as `WallpaperTile`s there. The illustration could not hold them: it is a picture, hidden from VoiceOver, so a button in it could be neither read nor pressed. It comes and goes with its step without animating: the height snaps, and an accessory fading out would be drawn over the buttons that had already moved up into its place. A step with none takes no room.
- A button whose title changes is a new button (M7, `.id` on its title). Changed in place, with nothing animating, the prominent button's glass on macOS 27 stopped part way between the old width and the new: two overlapping capsules, the title cut through where they met ("Open System Se ttings…"), and it stayed so until something else redrew the card. Seen on onboarding's login card, whose buttons change within a step when macOS answers that the login item needs approval, pressed through Accessibility and by the fakes run's remote alike.
- A card alone (`stepCount` 1) shows no page dots (M7): the move-to-Applications card and the one after leaving are single cards, and one dot only said "Step 1 of 1".
- A step change is one crossfade under a card that snaps to its new height (M7 review, 2026-09-24). Recorded at 0.1x on the fakes run, onboarding's first card moving to the second came apart: the window and the card snapped shorter in one frame, while the dots started from where the first card had them, below its new bottom edge, and slid up for about 0.3 s; the samples went at once; and the second card's Not Now and Open at Login were at full strength while "Add a wallpaper" and the import's words were still fading. The dots' scoped animation had animated their move as well as their opacity (a view's own `.animation` reaches its place on screen, and they had moved up with the buttons), and the buttons, new views for new titles, were outside every animation. Now everything under the picture is one page per step (`.id(stepIndex)`, an opacity transition, the one scoped animation over `Duration.menu`), in a `geometryGroup` so that only the crossfade inside it animates and its place snaps with the card; the picture keeps its own crossfade, in step with it. The words, the accessory, the dots and the buttons leave and arrive together, and the dots are never where the last step had them. The page being left fades out at its own height, so the card clips its content to its shape: a step with samples is cut at the new card's edge, never drawn outside it. This replaces the three animations above (picture, words, dots) and the accessory that came and went without animating: its fade is now under the next step's buttons fading in, as the words' is under the next words. By Return still nothing animates.
- Each step opens with keyboard focus on its primary button, the one Return presses (M7 review). Left to AppKit, the focus went to the window's first control: onboarding's first card opened with the ring on the first sample, and the move card and the card after leaving on their secondary button, laid out before the primary. `.defaultFocus` did not hold (AppKit gave the focus to the first control when the window became key), so the card places it itself: when its window is key, on each primary button it has not focused yet, a new step or a new title within one, on the next turn once that button is in the window. The focus is keyed by step, because the step being left is still on screen, fading out, with a primary button of its own. A button the user tabbed away from keeps the focus when the window comes back to the front. In the Gallery the cards on one page each take it in turn; the last one keeps it.
- One height for every step (M7 review, the same day). Re-recorded on the merged build, the step change above still happened while the card changed height: the window dropped from 623 to 501 pt in the frame the crossfade started, the first card was drawn cut off inside the second's height (tiles cut at the bottom edge, their labels, dots and Choose File… gone), and for about 1 s at 0.1x the second card's dots and buttons sat over the first card's cut tiles. So the card no longer changes height between steps. `init(steps:stepIndex:…)` takes every step's words and buttons (`OnboardingCardStep`, which also says whether the accessory is that step's), lays out each step the card is not showing unseen (hidden, disabled, hidden from VoiceOver, with no shortcut or focus), and gives the page area the tallest step's height (`TallestPageLayout`): a shorter step's words stay at the top, and its dots and buttons at the bottom, where the tallest step has them. The crossfade then happens in a still frame: the step being left fades out where it was, whole, and the next fades in over it, their dots and buttons in the same places. Nothing is clipped; the card's clip stays as a guard. Onboarding's window is sized by it, so it stays one size for all three cards (the first, with the samples, is the tallest; the others keep its height, with room between their words and their buttons). The single-step `init` is unchanged and is as tall as its one step. A step that grows within itself (a longer failure, a pane fallback) still grows the card, without a crossfade. Rejected: animating the height, which the entries above rule out, and fading out and then in, which would need the card to hold the old step's views after its caller has moved on.
- A new step's primary takes the focus when the crossfade is over, and at once when Return changed the step (M7 review). Placed at once, its ring was drawn whole round the button still fading in, over the step fading out. The transaction of the step change says which it was; a transaction's animation completion never came, so the card waits the crossfade's length (`Duration.menu` at the motion speed). A new title within a step still takes it at once.
- A disabled card shows no focus (M7 review). While onboarding imports or makes Livepaper the wallpaper, the window disables the card, and its primary (Choose File…, Set as Wallpaper) kept its ring, disabled. The card now drops the focus when it is disabled, gives it back to the same button when enabled again, and leaves a new step's to the rule above.

### LoginItemRow
- Told its state (off, on, needs approval, not found); never asks `SMAppService`. The switch's binding reads the given state and its setter only calls `onChange`, so the switch can never disagree with System Settings.
- No animation at all: the state changes rarely and from outside, and a caption fading in would mean animating the row's height.
- Warnings are a symbol plus words, and are announced, since they appear while focus stays on the switch. Takes the app's name as a parameter.
- The switch reads "Open at Login, on, switch"; the value given to it is not spoken (a native switch keeps its own on/off), so the warning is spoken twice instead: announced when it appears, and as the next element after the switch. The switch itself carries a hint with the same words.
- Callers should hand the new state back in the same turn as `onChange`: a switch answered late slides on, back, and on again.

### PauseRuleToggle
- A native switch whose label is the whole row, so the words are clickable. VoiceOver reads the switch as "title, on, switch" and the detail as the next element; both are reachable.
- Symbols sit in a fixed 24 pt slot so titles line up across rows. Every row is at least 40 pt, with or without a detail line.
- A click on the words animates the thumb (`Spring.ui`), as a click on the switch does.
- An unavailable rule shows off and disabled without changing the stored value, so the preference survives a move to another Mac.
- The switch is named explicitly (M6): the title is its label, the detail and note its hint, and the row's words are hidden from VoiceOver so that nothing is read twice. In the app's Settings the accessibility tree showed the four switches with no title or description, found by role alone, while LoginItemRow's switch, which already named itself explicitly, had one: evidently a label of a symbol, two lines of text and a tap gesture is not one a switch names itself from. The detail is no longer the next element. Not yet walked with VoiceOver.

### StatusLine
- The one place a wallpaper service that has stopped responding is reported: a static warning symbol, the words, and Restart. No pulse.
- Only a change of kind crossfades (opacity, `Duration.hover`, one scoped animation that a caller's `withoutAnimation` still silences); text inside `.working` swaps in place, because a count can change many times a second.
- Always 40 pt tall, so the window never shifts when Restart appears, and Restart's hit area fills that height. Restart never truncates; the message gives way instead. Becoming degraded is announced to VoiceOver.
- As the popover's last row (2026-09-24). The user saw "Live on 1 display" sit high and left, with space under it. Measured in window captures of the fakes run: the words' descenders were 17 pt above the glass's bottom edge (19.5 pt under the baseline) while their first stroke was 12.5 pt from its side. The 40 pt line centres its words, which already leaves about 12 pt under them, the inset the popover keeps beside loose content (the glass's 4 pt and 8 pt); the glass's 4 pt content padding, there so the cards' corners are concentric with the panel's, came on top of it at the bottom. The footer now takes that 4 pt back (`padding(.bottom, -Spacing.tight)` in `PopoverView`, as RecentsStrip takes back its margins), so the line's box ends at the glass's edge: 12.5 pt under the descenders, the inset the popover keeps at its sides. Restart's target reaches that edge, still inside the popover. Horizontally the words started 1 pt left of Mute's speaker, 2 pt when it is slashed: LabelToggle centres its symbol in the 20 pt slot, so the glyph sits 3 to 4 pt inside the slot's edge, which the icon-side-minus-2 rule does not see. The line's leading inset is now `Spacing.small + Spacing.hairline`: the speaker with waves stands 1 pt out, as a symbol beside words does, and the slashed one lines up.
- The crossfade stays inside the line (M7 review, 2026-09-24). When an import grew the popover, a display going from "No wallpaper" to a full card, the line moved down in the same change as its kind; the "Importing" it was leaving, spinner and all, faded out where the line had been, over the recent wallpapers' scroll bar, for about 0.7 s at 0.1x. A view leaving with a transition stays where it last was on screen. The line is now a `geometryGroup`: its place is its container's and moves at once, and the words it leaves fade out where it now is, under the words it takes.
- A status line's words are a sentence without its full stop, the house voice of the import's and the Workshop's failure words, and of every line the app gives it ("Livepaper is not your wallpaper", "Restarted recently; try again at 10:10"). The package's own was the one that ended in one, "Wallpaper service not responding."; it is now "Wallpaper service not responding" (`StatusLineStatus.words`, tested, and Core's lines are tested for the same). The VoiceOver announcement reads the same words.

### LabelButton, LabelToggle and SymbolButton
- Made in M6 for the popover's footer, which had drawn its own: a label, an icon button, and a raw 14% fill that ignored Increase Contrast. A symbol and words, or a symbol alone, for a line of controls on a popover or card. Not glass (the popover is); 40 pt tall targets; `.press`.
- The symbol has a fixed 20 pt slot, the width of the speaker with its waves at callout size, so the words stay put when the caller swaps the symbol (Pause All for Resume All, the speaker for the slashed one). The symbol's side sits 2 pt closer to the edge than the words' side. The focus ring is the capsule the on pill fills.
- LabelToggle's on state is FitModePicker's pill (`Pill`: `primary` at 14%, 30% under Increase Contrast), one definition for both. Not the accent: the popover never makes the app active, and there the accent draws grey and reads as disabled. The fill is state and never animates, even inside a caller's `withAnimation`.
- LabelToggle reads as a toggle (the toggle trait, value On or Off) and keeps the caller's words as its label, so VoiceOver says "Mute" in either state. Not yet walked with VoiceOver.
- SymbolButton's title is its tooltip and its VoiceOver label, since nothing on screen says it. Its focus ring is a circle round the glyph, as TransportCluster's are: the 40 pt square is a hit area, not a drawn shape.
- Disabled dims to 40%, as CompactTextButton does: `.press` is a custom style, so nothing else would show it.
- A key press on any of them goes through `withoutAnimationIfKeyPress`.

### FavouriteToggle
- The heart beside a wallpaper's name in the inspector, moved here from the app in M6. An outline in `secondary` when off; filled in the accent when on, as SidebarRow marks its selection (the library window is active, so the accent draws). `.title3`, a 40 pt target, a circle focus ring.
- No motion: it is state, and `.animation(nil, value:)` keeps a caller's `withAnimation` off it. A key press goes through `withoutAnimationIfKeyPress`.
- The tooltip says what a click does, "Favourite" or "Unfavourite". VoiceOver reads a toggle labelled "Favourite", On or Off; the word is the one WallpaperTile reads for a favourite. Not yet walked with VoiceOver.
- Disabled dims to 40%, as the other M6 controls do.

### WorkshopGetButton
- The Workshop window's primary action (M12, record 0009), built as SetOnDisplayButton is: one `glassProminent` button in the toolbar, the title "Get" fixed, and a 16 pt icon slot shared by the arrow, the spinner and the checkmark, so the title never moves. Idle to done is a symbol replace (`arrow.down` to `checkmark`); the spinner crossfades over `Duration.hover`, with the same `accessibility.fade` and `symbolReplace` as SetOnDisplayButton.
- Four states: idle; working (disabled, while the item is downloaded or imported); done (enabled, as SetOnDisplayButton's `.done` is: getting it again is a duplicate the import names); unavailable, disabled with its reason as the tooltip and as what VoiceOver reads after "Get". The reason is the import's own words, for a web or application item, or "Go to an item’s page to get it".
- It lives in the toolbar rather than over the page: the page is Steam's, and the toolbar is the floating layer where glass belongs. A key press goes through `withoutAnimationIfKeyPress`.
- Seen in the Gallery on 2026-09-23, dark, window inactive (the accent needs a key window); not yet walked with VoiceOver or recorded at 0.1x.

### SteamSignInForm
- The sign-in sheet's content (M12): the account name and password, then what Steam Guard asks, a code from the email or the Steam Mobile app, or an approval in the app, and the working step while Steam's download tool is set up or signs in. It is told the step and holds nothing: the fields are the caller's bindings, so the password stays in the sheet's state and in the one sign-in it is handed to.
- No motion at all: every step comes from Steam's answer, not from the user's hand, as LoginItemRow's states come from outside. The sheet's height snaps to the step's.
- 440 pt wide, `Spacing.extraLarge` around, `Spacing.large` between parts, as NamePrompt's sheet. The header's symbol and the approval's spinner share one 40 pt column, so the step's words line up with the title. The fields are a `.columns` form, labels trailing, with `textContentType` `username`, `password` and `oneTimeCode`, so the user's password manager can fill them.
- A problem is a symbol and words in red, never colour alone, as ImportProgressRow's failure, and is announced; so are the code and approval steps, which appear while focus stays where it was. Focus moves to the first empty field on each step.
- The code field is `title3` monospaced, 140 pt: a five-character Steam Guard code with room to spare. Its prompt is "Code" (the whole label, "Steam Guard code", is VoiceOver's), because the longer prompt was cut off at that size (seen in the Gallery).
- Seen in the Gallery on 2026-09-23 in every step, dark, window inactive; not yet walked with VoiceOver.
