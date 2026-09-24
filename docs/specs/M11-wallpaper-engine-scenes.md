# M11: Wallpaper Engine scenes

Import Wallpaper Engine scene items and draw them live in the wallpaper extension with Metal, and import a GIF scene as an ordinary video wallpaper. Lanes A and C together, since the model, the importer and the engine all change. It is built before M7-system-integration.md, at the product owner's request. See record 0007 (scenes drawn live, a GIF scene made into video, web and application items still refused), 0002 (the library, and the extension's read-only access to it), 0001 (the render host, and the layer tree made before the context is hosted), `Spikes/results/S10.md` (a Metal layer and a display link inside the extension) and `CONTEXT.md`.

## Rules

- Code goes in `LivepaperCore` (the model), `LivepaperImport` (discovery and the scene stages), a new nonisolated target `LivepaperScene` in `LivepaperKit`, `LivepaperPlayback` (the Metal slot, `SceneEngine`, `SurfacePlayer`), `WallpaperExtension/` and `App/`. `LivepaperScene` holds the Wallpaper Engine formats the product needs, the GIF-scene rule, the `SceneDrawing` seam and what draws a scene behind it (`WallpaperEngineScene`), and the programs both sides share (`ScenePrograms`). The shader translation and `ScenePreparation` are `LivepaperImport`'s, since only the app runs them. `LivepaperImport` and `LivepaperPlayback` depend on `LivepaperScene`; it depends on neither.
- Nothing blocks on the cooperative pool (M4-import.md, "As built"). Writing a GIF scene's intermediate file runs on a thread of its own (`onOwnThread`), as every writer does. `SceneEngine` loads a scene on a queue of its own and draws on a render thread of its own, which runs the display link.
- The extension reads the library and nothing else (record 0002). A scene is loaded from its folder in the library, and every path comes from a `LibraryPath` through `LibraryLocation`. The names a project gives are checked for containment, as M4 checks a video item's.
- Test-first with Swift Testing table tests, on tiny synthetic fixtures that the tests make themselves: a `project.json`, a package of a few entries, a sprite sheet of a few pixels. Never Workshop files. They are other people's work and never go into the public repository. The user's samples are used only in the checks on screen, from where they sit on this Mac.
- The video path is unchanged, and so are its tests. The only rows that change are the ones that expected a scene to be refused.
- Vocabulary is `CONTEXT.md`'s: wallpaper, scene, GIF scene, library, import, source file, optimised copy, poster, display, surface, render host, loop seam. No type is named for a renderer, and a wallpaper is never a video, clip or asset in a name.
- Anything adapted from another project keeps its attribution in `NOTICE`, and no GPL project is read (M5-engine.md's rule).
- CI builds with Xcode 26 on macos-26, which is older than the local toolchain, so keep to what Xcode 26 has (CLAUDE.md).

## What earlier milestones settled

- **Import** (M4-import.md). The stages run discover → fingerprint → probe → plan → convert → write the optimised copy → validate → artefacts → commit. Work happens in `.staging/<id>/` inside the library. The commit is a rename, then the manifest through `ImportLibrary.insert`, and `sweepInterruptedImports` clears whatever an interrupted import left. The ffmpeg helper converts a GIF (record 0006). The hover preview is optional. A Wallpaper Engine folder is recognised by its `project.json`, and the paths it names are checked to stay inside the folder.
- **Engine** (M5-engine.md). A surface's layer tree is built before the first reply, because a layer added to a hosted context does not composite. `PlaybackSupervisor` maps `decidePlayback` onto each surface. A stopped state holds the poster and releases the decoders. The watchdog counts displayed pictures against the frames fed (`judgeProgress`, with `notComposited` for a covered surface) and climbs `.flush` → `.rebuildSurface` → `.rebuildPipeline` → `.restartAgent`. The extension reads `render-state.json` with its fallbacks.
- **Screens** (M6-screens.md). A tile goes live on its hover preview through `PreviewPlayer` and otherwise shows the poster. The inspector shows a preview and a `DetailsList`. `RenderState.make` is the one way a render state is made, and the import list's words live in `stageWords`.
- **S10** (`Spikes/results/S10.md`). A `CAMetalLayer` in the tree before hosting, at opacity 0 and revealed by an opacity change, composites (measured). `CAMetalDisplayLink` fires in the extension on a thread with its own run loop, with `preferredFrameRateRange` pinned (measured). A heavy load held 30 fps but not 60 (measured, on a busy machine). `top`'s power score does not see the GPU. Cover, sleep and wake were not run with Metal.

## The model

A wallpaper is a video or a scene. `Wallpaper.kind` is `.video` or `.scene`.

| Change | Holds |
|---|---|
| `Wallpaper.scene: WallpaperScene?` | Nil for a video. `WallpaperScene` holds `project`, the `LibraryPath` of the item's `project.json`, and the scene's size from its `general.orthogonalprojection`, which is what a `Presentation` fits to a display |
| `optimisedCopy` of a scene | Names its package, so a Livepaper that knows only video fails to play it and holds the poster |
| `details` of a scene | The scene's size, 30 fps (the rate it is drawn at), no length, and the bytes of its folder |
| `library.json` 1.1 | A minor version that only adds `scene`. A 1.0 reader ignores it, and a 1.1 reader takes a missing one as nil. `library-v1.1.json` joins `library-v1.0.json`, which still loads |
| `render-state.json` 1.1 | `RenderState.Display.scene`, the same way. `render-state-v1.1.json` joins `render-state-v1.0.json` |

A scene wallpaper's folder keeps the following files, and not the item's `shaders/` folder, which is Wallpaper Engine's DirectX shader cache:

| File | Is |
|---|---|
| `project.json` | The item's own |
| `scene.pkg` | The package, named after the project's `file` with `.pkg` |
| `preview.jpg` or `preview.gif` | The item's preview file, under its own name |
| `poster.heic` | The scene drawn offscreen, 10 s in, at its own size up to 3840 on the longest side ("As built", Stopped scenes and their posters); when it cannot be drawn, the preview's first frame, cut to the scene's shape, since a Workshop preview is square |
| `hover.mov` | Only when the item has a `preview.gif`. The ffmpeg helper converts it as the importer converts any GIF, and it is then made into a hover preview. Optional, as for video |

## Wallpaper Engine's formats

What the product reads, as S9 learned it from the samples (`Spikes/S9/Sources/SceneItemFormat/`):

- **`ScenePackage`** (`.pkg`): a u32 length and "PKGV00xx", a u32 entry count, then per entry a u32 name length, the name, a u32 offset and a u32 size. Offsets count from the end of the table.
- **`SpriteSheet`** (a `.tex`): the sections "TEXV0005", "TEXI0001", "TEXB000n" and "TEXS000n". The frames are raw RGBA8888, LZ4-compressed (raw block) or not, or an encoded image. "TEXS" lists each frame's atlas, its time and its rectangle.
- **The GIF-scene rule**: the scene's only content is one image layer whose texture is an animated sprite sheet, with no effects and no particles.

## Import

`discoverSources` accepts scene items. A scene becomes an `ImportCandidate` whose `source` is the package and which carries `scene: SceneItem?`. A project counts as a scene when its type is `scene` (Botanical's, a GIF-template project, says so too). Web and application items are refused with `WallpaperEngineProjectError.runsCode(String)`, whose words say that only video and scene items can be imported. A scene folder without its package is skipped (`SkipReason.noScenePackage`). Video items are discovered as before.

A scene:

| Stage | Does | Tested by |
|---|---|---|
| Fingerprint | SHA-256 of the package. A match in the library ends the import as a duplicate before anything else | The same synthetic package imported twice from folders with different names |
| Probe | Reads the package's table and its `scene.json`: the size from `general.orthogonalprojection`, and whether the GIF-scene rule holds. A scene with no orthogonal size is refused, with a reason the UI can show | Synthetic packages: with a size, without one, a truncated table, an entry running past the end of the file |
| Prepare (`ImportStage.prepare`, "Preparing the scene") | Copies the project, the package and the preview into `.staging/<id>/`, then runs `ScenePreparation.prepare(_:tools:)` on the staged folder, which translates every program the scene draws with and writes `scene-programs.json`. A scene that cannot be prepared is still imported, and holds its poster until the app prepares it | The staged files, the hook called once on the staged folder and what it writes committed, a scene whose preparation fails imported without programs |
| Artefacts | The poster drawn from the scene, or, when it cannot be drawn, from the preview's first frame, cut to the scene's shape; the hover preview from a `preview.gif` | A scene drawn gives its own picture at its size, capped at 3840; one that cannot be drawn and a square preview give a 16:9 poster from the preview; a GIF preview gives `hover.mov` and a JPEG gives none |
| Commit | Rename, then the manifest, as for video | A manifest entry with `scene` set, and a folder holding exactly the files above |

A GIF scene:

| Stage | Does | Tested by |
|---|---|---|
| Fingerprint, probe | As for a scene. The probe finds the GIF-scene rule holds and finds the sprite sheet | The GIF-scene rule's table |
| Convert | The sprite sheet's frames, in order, into an intermediate ProRes file in `.staging/<id>/`, at the frames' own rate | A synthetic sprite sheet of a few frames over two atlases gives a file with those frames, in order, at that rate |
| Plan, write, validate, artefacts, commit | M4's video pipeline on the intermediate. The intermediate never reaches the library | A video wallpaper (`scene` nil) whose optimised copy passes the loop-seam validator, the fingerprint being the package's |

## Playback

A scene pauses, resumes and is watched exactly where a video is. The pause rules, `decidePlayback` and the supervisor's decisions are unchanged, and so is the video path.

| Part | Module | Does |
|---|---|---|
| Metal slot | `LivepaperPlayback` (`SurfaceTree`) | A `CAMetalLayer` made with the rest of the tree before the context is hosted, above the video layers, at opacity 0. It is shown and hidden by an opacity change and never added later (S10). Laid out by `pictureRect` from the scene's size and its `Presentation`, as a video of that size would be |
| `SceneEngine` | `LivepaperPlayback` | Drives one Metal slot with `CAMetalDisplayLink` at 30 fps, on a render thread of its own. Draws the `SceneDrawing` at the scene time, which it keeps across pause and resume. Counts the pictures its GPU finished for the watchdog (`displayedPictures(over:)`), as a video counts its renderer's, and each committed frame as fed; a link the system stops calling while the engine stands ready is `withheld`, read as `notComposited` ("As built", Liveness) |
| `SurfacePlayer` | `LivepaperPlayback` | What the supervisor drives per surface. A video goes to `SurfaceLayers` as before. For a scene it holds the poster on `SurfaceLayers` with the decoders released, shows the Metal slot and runs the scene engine. Pause keeps the scene loaded and stops the link; suspend also releases the scene; stop releases everything, and hold-still releases the scene but keeps its last picture up ("Stopped scenes and their posters", below). On the recovery ladder, `.flush` restarts the link, `.rebuildSurface` makes a new one and `.rebuildPipeline` loads the scene again. It switches between a video and a scene in both directions |
| `SceneDrawing` | `LivepaperScene` | The seam: load a scene from its folder in the library with a Metal device; draw into a texture on a command buffer at a scene time in seconds; resize |
| `WallpaperEngineScene` | `LivepaperScene` | Spike S9's drawing, ported: layers, effects, puppets, particles and bloom, from the programs the import translated. A scene it cannot load holds its poster, still |
| Extension | `WallpaperExtension/` | Reads `RenderState.Display.scene`, resolves the scene's folder through `LibraryLocation`, gives each surface a `SurfacePlayer` and the scene engine a Metal device. Logs a scene's load, its link starting and stopping, and the ladder's scene steps under the `surface` and `supervisor` categories |
| App | `App/` | Scene wallpapers appear, preview, can be set, paused and deleted like video ones. A tile and the inspector preview `hover.mov` when there is one and otherwise show the poster. The inspector's details for a scene are Kind ("Wallpaper Engine scene"), Resolution, Frame rate, Size and Imported, with no Length or Codec. Nothing else in the design system changes |

## Seams for test-first work

Swift Testing table tests under `swift test`, with an injected clock, fakes and fixtures that the tests write. None reads a Workshop file, and none needs a display.

| Seam | Tested as |
|---|---|
| Package reader (`ScenePackage`) | Entries read back by name, with offsets counting from the end of the table; a version other than "PKGV"; a count the file cannot hold; a truncated table; an entry past the end of the file |
| Sprite-sheet reader (`SpriteSheet`) | Raw RGBA8888, LZ4-compressed and encoded frames; frames over two atlases with their times and rectangles; a texture with no "TEXS" section (not animated); an unknown section version refused |
| GIF-scene rule | One image layer with an animated sprite sheet is a GIF scene. An added effect, an added particle system, a second layer or a still texture each make it not one |
| Orthogonal size | `general.orthogonalprojection` with a width and a height gives the size. A missing projection, or one without both, is refused with a reason |
| Project parsing and discover | Type `scene`; `web` and `application` giving `runsCode` with its words; video unchanged; a scene folder without its package giving `noScenePackage`; the package named from `file`; a name escaping the folder |
| The importer on a synthetic scene | Stages in order (fingerprint, probe, prepare, artefacts, commit); the folder's files; the manifest entry; the hook called once; a duplicate; no orthogonal size, an unreadable package or scene, and no preview each refused, leaving nothing in `.staging/` |
| The importer on a synthetic GIF scene | Stages in order (fingerprint, probe, convert, then the video stages); a video wallpaper; the validator passes; no intermediate left; the package's fingerprint |
| Manifest and render-state codecs | 1.1 round trips; `library-v1.1.json` and `render-state-v1.1.json`; the 1.0 fixtures load with `scene` nil; the same state gives the same bytes |
| Surface calls for a scene | `surfaceCalls` rows: a scene is mapped as a video is, video → scene and scene → video included. `SurfacePlayer` on a real layer tree with a drawing that draws nothing (on a GPU): play holds the poster and shows the slot; pause keeps the scene, suspend lets it go and resume loads it again; hold-still keeps the scene's last picture on the slot and releases the scene, and nothing and a video hide the slot and release it; another scene replaces the one up; a scene that cannot be drawn holds its poster; the watchdog counts a playing scene and nothing of a paused one |
| Scene engine bookkeeping | `SceneClock`, pure: scene time advances only while running, holds across pause and resume, never runs backwards, and starts at zero after a reset. `SceneTally`: the pictures the GPU finished, the frames committed and asked for, and the window server's presented times over a window; a silent link while the engine stands ready is `withheld` |

## Checks on screen

On this Mac's one display, with the user's nine samples: seven scenes, one of them the GIF scene Botanical, and two video items. Each row's log excerpt goes into the PR. The scene live on the desktop and the switches go in as video, and a scene tile and the inspector's details as screenshots (CLAUDE.md). Captures are of the desktop's wallpaper window alone (WindowManager's, by window id, as S10 took it), never of the display.

| # | Check | Pass when |
|---|---|---|
| 1 | Import all nine samples through `LivepaperImport`, then one of them again | Six scene wallpapers and three video wallpapers, Botanical among the videos. Each scene's folder holds the files in the model's table and no `shaders/`. The repeat is a duplicate before any conversion, and `.staging/` is empty |
| 2 | Set Lonely Cat (3289988463) on the desktop | The extension's log shows the scene loaded and the link started on the desktop surface, and `notifyutil -p app.livepaper.check` gives a `check count` of about 30 pictures a second displayed and fed, verdict `healthy`. Two captures a second apart differ where the poster pans |
| 3 | Pause and resume by the pause rules: a fullscreen app over the desktop, then gone; the user's pause, then resume | The display pauses (`decision … pause.desktopCovered`, `pause.user`), the link stops and no pictures are presented. On resume the scene goes on from where it stopped, healthy |
| 4 | Switch video → scene → video | Each switch happens in place, with no dark frame. While the scene shows, the extension holds no decoder session; while the video shows, the Metal slot is hidden and the scene released |
| 5 | Set Botanical (2987840102) | It plays as a video: with "Log Playback Metrics" on, 20 loops show no presented gap over 1.5 frame durations at a seam |
| 6 | Leave the desktop live on Botanical | The desktop shows Botanical when the milestone is handed over |

## Done when

- The seam tests pass with `swift test --package-path Packages/LivepaperKit`, locally and in CI. `library-v1.1.json` and `render-state-v1.1.json` are checked in, and the 1.0 fixtures still load. `make gen build test lint` is green.
- The video path's tests pass unchanged, except for the rows that expected a scene to be refused.
- Every row of the checks table passes, with its evidence in the PR.
- `SceneDrawing` has one implementation, `WallpaperEngineScene`, and import calls `ScenePreparation.prepare(_:tools:)`, which translates the scene's programs ("As built", S9 ported).
- An "As built" section, as M4-import.md's, records what was decided on the way and the exact wording of every new log line, for M7-system-integration.md, M8-hardening.md and the port of S9.

## Out of scope

Energy numbers, for scenes as for video (M8-hardening.md). Scene scripts, scenes that show the time or the date, and web and application items (record 0007). Audio-reactive input: capturing the system's audio needs a permission decision, so it stays silent. Unpacked scene folders without a package. Changing a scene's user properties: they take the item's defaults. (Drawing scenes, translating their shaders, their sounds and their user properties' defaults came in with the port of S9; see "As built".)

## As built

What M11 decided or found on the way, for M7-system-integration.md, M8-hardening.md and the port of S9. Names are quoted from the code.

### The seam S9 plugs into

`LivepaperScene/SceneDrawing.swift`:

```swift
public protocol SceneDrawing: AnyObject {
    init(folder: URL, device: any MTLDevice) throws
    func draw(into texture: any MTLTexture, on commandBuffer: any MTLCommandBuffer, at time: Double)
    func resize(width: Int, height: Int)
}
```

- `init` runs on a load queue of its own, then the drawing is used on the render thread only, one call at a time. A throw holds the poster (`scene: surface … cannot load …`). `folder` is the wallpaper's folder (`SceneFolder`: `project.json`, the package named by `SceneFolder.package(for:)`, `poster.heic`, `hover.mov`). The texture is `SceneFolder.pixelFormat` (`bgra8Unorm`), the Metal slot's drawable; the engine commits the buffer and presents it. `resize` comes before the first `draw` and whenever the drawable's size changes, on the render thread.
- The extension names the one implementation in `HostedSurfaces.host` (`drawingType: WallpaperEngineScene.self`, since the port). Its import-time work goes in `ScenePreparation.prepare(_:tools:)`, which runs on the staged folder with the item's files in it; what it writes is committed with them. Only a cancel throws, and it leaves nothing behind; a scene that cannot be prepared is imported without programs ("Preparation", below). S9's `ProgramManifest` (`scene-programs.json` beside the item's files, `Spikes/results/S9.md`) fits there as it is.
- `PosterScene`, the stand-in that drew the poster drifting and pulsing, is gone: the user found it looked like a bouncing logo. Until a scene can be drawn for real its surface holds the poster, perfectly still.

### Model and import

- `Wallpaper.scene: WallpaperScene?` (`project`, `width`, `height`) and `kind`; `RenderState.Display.scene` the same. Both files are 1.1. A scene's `optimisedCopy` is its package, which an older build fails to play and so holds the poster. A video's JSON is what it was, `scene` absent. The one 1.0 test that wrote `"minor" : 0` into a string now writes the current minor, and "writes its schema version" reads 1.1.
- `ImportOutcome.importedScene(Wallpaper)` for a scene kept to be drawn (nothing to report of an optimised copy); a GIF scene is `imported(_, report)` like any video. `ImportError.scene(SceneReadError)` and `.sceneWithoutSize`, `SkipReason.noScenePackage`, `WallpaperEngineProjectError.runsCode`. `ImportStage.prepare` sits between `validate` and `artefacts`. The words are pinned in `ImportWordsTests`.
- A scene's name is its project's title, or its folder's name (the Workshop number) when it has none. Its details are the orthogonal size, 30 fps, no length, codec `scene` and the bytes of its folder; the inspector shows Kind, Resolution, Frame rate, Size and Imported (`Wallpaper.detailsShown`, Core). The inspector's preview plays a scene's `hover.mov` over the poster, or nothing.
- **The GIF-scene rule** (`readSceneOutline`) is stricter than "one image layer": exactly one object, an `image` and nothing else (`particle`, `sound`, `text`, `model`, `light`, `animationlayers`), no effects, visible as a plain `true`; its `size` the scene's and its `origin` the centre, with scale, angles, colour, alpha and brightness absent or plain identity (a value bound to a user property fails); no scene-wide bloom or camera shake; a model without a puppet; one material pass with a `genericimage*` shader and one texture. The texture must then read as a sprite sheet of two or more frames (`SpriteSheet`): raw RGBA8888 (LZ4 or not) or ImageIO-encoded, frames axis-aligned, inside their image and shown for a time. Anything else is drawn live, so a GIF scene imported with "Compressed (DXT5)" goes to the renderer.
- The frames go to ProRes 422 at the shortest frame's time on a 6000-tick clock (`spriteSheetRate`: 0.1 s is 600/6000, 60 fps at most), longer frames held by `ConstantRateResampler`, over the scene's clear colour; the planner then transcodes it as any ProRes file. Botanical's two atlases (7680×7560 and 5760×4320) decode to 330 MB for the length of the conversion, in the app.
- The poster is cut about its middle to the scene's shape (a 1024² preview gives 1024×576), so the still, the inspector and the focal-point editors line up with the scene. With no preview there is no poster, and the import fails (`ArtefactError.noPicture`). Since 2026-09-24 the poster is drawn from the scene when it can be, and a scene with no preview is then imported ("Stopped scenes and their posters", below).
- `LivepaperScene` depends on Core only. The package reader maps the file. Workshop JSON may start with a byte-order mark; a JSON `true` is told from a `1` by its CF type, since Swift's `as? Bool` takes both.

### Playback

- `SurfacePlayer` wraps `SurfaceLayers` and leaves it as it was; the extension's `makeSurface` returns it and `HostedSurface` keeps it. The Metal slot is `SurfaceTree.scene`, the tree's last sublayer, laid out by `layerFrame` from the scene's size, drawable at the frame's pixels (at most 16384 a side). Its device is set on the first load, so a surface that only plays video never touches Metal.
- A scene: the poster held on the layers (their decoders released), the slot hidden, the scene loaded, the link started, and the slot shown once the first picture is drawn (a command buffer completed), at most 1 s later. To a video: the link stopped, the video started on the layers under the slot's last picture, then the slot hidden and the scene released. Pause stops the link; suspend also drops the drawing and resume loads it again; nothing and a video release it; hold-still of the scene up keeps its last picture in the slot (changed on 2026-09-24, "Stopped scenes and their posters" below), and of anything else releases it; the same scene with a new presentation is laid out in place. `.flush` and `.rebuildSurface` make a new link, `.rebuildPipeline` loads the scene again. There is no crossfade into or out of a scene: the poster or the last picture bridges the cut.
- `SceneEngine` runs every surface's link on one thread with its own run loop (`SceneRenderThread`), one device and one command queue (`SceneGPU`), `preferredFrameRateRange` pinned to 30 and `preferredFrameLatency` 2. Scene time (`SceneClock`) is the link's target time since the run's first frame, carried across pauses. The watchdog's `displayed` is drawables with a presented time, `fed` the frames committed (`SceneTally`).

### Log lines

The extension, category `surface`, `.notice` unless marked; `<S>` is the surface ID, `<W>` the wallpaper's folder, which is its ID:

- `scene: surface <S> loaded <W> in <n> ms, drawn by <type>`
- `scene: surface <S> cannot load <W>, holding the poster: <domain> <code>: <description>` (`.error`)
- `scene: surface <S> has no Metal device, holding the poster` (`.error`)
- `scene: surface <S> drawing at 30 fps from <t> s`
- `scene: surface <S> first picture drawn <n> ms after the start`
- `scene: surface <S> shows <W> in the Metal slot`, or `…, with no picture after 1 s`
- `scene: surface <S> stopped drawing at <t> s (<pause|suspend|still|stop|restart>)`
- `scene: surface <S> holds <W> still on its last picture, at <t> s` (a still of the scene up: the slot keeps its picture, the scene let go; since 2026-09-24)

The supervisor's lines are M5's, unchanged: a scene's `now showing`, `decision`, `check count` and `check verdict` read as a video's.

The app, category `app` (since 2026-09-24), at import after `import finished` and at launch after the scenes are prepared:

- `scene: poster of <id> drawn from the scene, <w>x<h> at 10 s`
- `scene: poster of <id> not drawn from the scene, so it is the preview's: <reason>` (`.error`)

### The checks, run on one MacBook display (macOS 27.0), 2026-09-23

The user's windows covered 90 % of the desktop throughout, and the pointer and keyboard were not touched. The samples were imported by a scratch harness through `LivepaperImport` into the real library while the app was quit, with Homebrew's ffmpeg for the GIF previews (no helper is built in this checkout); displays were set by editing `app-state.json` with the app quit, and switched in place by writing `render-state.json` as the app would and posting its notification.

| # | Result |
|---|---|
| 1 | Pass. Six scenes kept (Gaze 6000×3375, A Lonely Winter, Jet Lag, Agamemnon and Lonely Cat 3840×2160, Backstreet Lofi 1920×1080; hover previews for the four with a `preview.gif`) in 0.1 to 0.3 s each; Botanical a 4.0 s, 10 fps video whose seam passed, in 0.5 s; the two video items as before (one transcoded in 108 s, one remuxed). No `shaders/` kept. Lonely Cat and Botanical again: duplicates, nothing written, `.staging/` empty |
| 2 | Pass for the Metal slot. After the agent restart (held by the ten-minute gap until 20:58:21): `loaded … in 281 ms, drawn by PosterScene`, `drawing at 30 fps from 0.00 s`, `first picture drawn 34 ms after the start`, `shows … in the Metal slot`. Captures of the wallpaper window a second apart differed in 32 % of their pixels. The watchdog's count was `displayed=2`–`4 expected=60 fed=60`–`64`, verdict `notComposited`: the window server presented the covered slot one or two times a second. Botanical under the same windows counted `displayed=20 expected=20`, healthy, since a video's count is the layer's own. A scene's count with the desktop in view is not measured yet |
| 3 | Pass for the user's pause: `decision … pause.user`, `stopped drawing at 21.33 s (pause)`, no pixel changed in a second; resumed `from 21.33 s`. A covering fullscreen app was not tried (no pointer) |
| 4 | Pass: scene → Botanical in place (`stopped drawing at 119.52 s (pause)`, then `now showing`), Botanical → scene (`loaded … in 16 ms`, first picture 38 ms later). The decoder check was not run |
| 5 | Pass: `loops 20, seams watched 15, seam step 1.00, … gaps over 1.5 at seams 0, elsewhere 0, renderer dropped 0 of 1273` |
| 6 | Pass: the desktop was left live on the imported Botanical (`5935CA29-…`), the app running, the probe off. Quitting first held Lonely Cat's poster (no pixel changed) |

### S9 ported: scenes drawn for real

Done on 2026-09-23, after the checks above. Spike S9's reader, shader translation, preparation and drawing (`Spikes/S9/`, `Spikes/results/S9.md`) are in the product, with S9's structure and the house's names: no type is named for a renderer (`SceneRenderer` is `WallpaperEngineScene`), `ProgramManifest` is `ScenePrograms`, `TexFile` is `SceneTexture`, `PuppetModel` is `ScenePuppet`, `ItemFiles` is `SceneFiles`, and `JSONValue` is `SceneValues`.

**Where the code is.** `LivepaperScene`, which the extension and the app both link: the reader (`ScenePackage`, `SceneTexture`, `ScenePuppet`, `SceneFiles`, `SceneDocument` with `SceneLayer`, `SceneEffect`, `SceneMaterial`, `SceneParticles` and `SceneSound`, `ParticleDefinition`, `SceneValues`); what both sides share of the programs (`ScenePrograms`, `ProgramRequest`, `TranslatedProgram`, `UniformLayout`); and the drawing (`WallpaperEngineScene` with `SceneLayerDrawing`, `EffectChain`, `MaterialDrawing`, `CompiledPrograms`, `BasePasses`, `SceneTextureStore`, `PuppetMesh`, `ParticleGroup`, `ParticleSystem`), our stand-in textures (`ParticleTextures`) and the scene's sounds (`SceneSoundtrack`). `LivepaperImport`, which only the app links: `ShaderTools`, `ShaderTranslator`, `ShaderAnnotations`, `ShaderHeaders`, `BaseMaterials` and `ScenePreparation`. The sandboxed extension never translates: it compiles the Metal the app wrote. `SceneFiles` reads only the package, so a name in a scene cannot lead out of it. The seam kept its three calls and gained three with defaults: `notes` (what is not drawn as the scene asks, logged once after a load), `makeSoundtrack()` (made on the loading queue, then played on the engine's owner's actor) and `pointerMoved(to:)` (before each `draw`).

**The shader tools** are a helper built from pinned sources, as ffmpeg is (record 0008, `Helpers/shader-tools/`): glslang 16.6.0 and SPIRV-Cross vulkan-sdk-1.4.357.0, compiled with the system's clang (no CMake), bundled next to the app's executable and found by `ShaderTools.locate`, their licences in `Helpers/shader-tools/licenses/` and `NOTICE`, and a CI job that builds them for the `check` job (`LIVEPAPER_REQUIRE_SHADER_TOOLS=1`). A helper rather than linking the libraries: it is the ffmpeg machinery reused, a crash or a hang on a Workshop item's shader ends a process with a time limit and never the app, and no C++ enters the Swift package. Each tool run is sealed like ffmpeg's: fixed arguments, an empty environment, nothing on its input, 5 s and 16 MB limits, stopped on cancel.

**Preparation.** At import `ScenePreparation.prepare(_:tools:)` runs on the staged folder: every `ProgramRequest.all(in:)`, from the item's own shader source or else our base material, translated and written as `scene-programs.json` with `translator` 1 (`ScenePrograms.currentTranslator`) and the tools' versions. A scene that cannot be prepared (no tools, a scene that does not read) is imported anyway, without programs, and says why: `ImportOutcome.importedScene(_, preparation:)`. At launch, after the sweep, the app prepares again every scene whose programs are missing or from another translator (`ScenePreparation.refresh`, one scene at a time, off the main actor), writing the file whole or not at all. On this Mac the six scenes imported earlier, without programs, were prepared on the first launch of the build: 3, 4, 10, 27, 2 and 9 programs, none failed, 8.6 s in all (Backstreet Lofi alone 4.2 s). A tiny program takes about 150 ms, six tool runs.

**Drawing.** As S9 drew, with these changes:

- Load ends by drawing one small picture offscreen, so that every pipeline and mipmap is made while loading and not in the surface's first frames. Loads took 118 to 1142 ms on the desktop, the first picture 31 to 65 ms after the start.
- A scene that cannot be loaded, above all one with no programs yet, throws (`WallpaperEngineScene.LoadError`, which reads in the log) and its surface holds its poster, still.
- Particle vertices go into three buffers per system taken in turn, grown as needed, instead of a new buffer each frame. A time that jumps ahead or back re-simulates the last half minute, which is longer than any particle lives.
- An object's colour (`instanceoverride.colorn`) replaces its preset's random colour, where its other overrides scale the preset's values. Inferred: A Lonely Winter's sakura, pale pink in the preset and near white on the object, are white in Wallpaper Engine's own preview, and its light shafts, warm in the preset and white on the object, are white there too.
- Particle textures that ship with Wallpaper Engine are drawn by us (`ParticleTextures`, written from scratch; `util/*` as S9 had them): a soft glow (`halo`, `halo_2`), a small bright dot (`chromaticdot`), soft irregular puffs (`fog1`, `fog3`, `smoke2`), long soft beams (`light_shafts_0`, `light_shafts_6`), thin streaks (`beam_1`, `drop`), a 4 × 4 sheet of petals, leaves and flakes (`debris1`) and one of an expanding ring (`misc/wave`), a flat normal map (`normal_splash`), and by keywords for any other name. A particle picks one frame of a sheet for `randomframe` and steps through them over its life for `sequence`.
- Sound objects play (`SceneSoundtrack`): from the package, at the scene's volume times the wallpaper's, which starts muted; looping for `loop`, once otherwise; started, paused and stopped with the drawing; nothing decoded while muted. A sound that starts silent or is not visible stays silent. Jet Lag has a music track and Backstreet Lofi a storm; neither was heard on screen, since the wallpaper stayed muted while the user might be on a call. The tests use silence.
- User properties take the item's defaults from its `project.json` (`SceneValues`), a combo's condition included: Backstreet Lofi's rain shows, and of its screens the first.
- The pointer: `NSEvent.mouseLocation` reads in the sandboxed extension (`extension: pointer read x=700 y=1073 on display 0,0 1800x1169`), so the extension gives it to the drawing each frame (`DisplayPointer`). Camera parallax (Agamemnon, `cameraparallax` true) moves each object against the pointer by `cameraparallaxamount` × its `parallaxDepth` × half the scene at the display's edge, eased by `cameraparallaxdelay`; `g_PointerPosition` and `g_ParallaxPosition` get the pointer too. The formula is inferred, not measured against Wallpaper Engine.
- GPU time a frame, offscreen at the desktop's drawable size (4156 × 2338): Backstreet Lofi 8.5 ms, Agamemnon 7.9 ms, A Lonely Winter 3.2 ms; at 1920 × 1080 the six took 1.1 to 6.6 ms. Measured on a machine doing other work.

**Liveness.** M11's check saw the watchdog read a scene as `notComposited` (2 to 4 of 60 pictures) under windows that covered most of the desktop, while a video read healthy under the same windows. The two counts measured different things. A video's is its renderer's own displayed picture, which advances whether or not the window server composites it. A scene's was the window server's presented time of each drawable, and under windows the window server presents the desktop a few times a second: 3 to 7 of 60 with the user's windows as they were, 26 when the Library window was open over them, and no more in Fit than in Fill (so not the slot's size or its clipping). S10 saw nearly every frame presented during a FaceTime call, which keeps the display busy. Setting the slot's device before hosting, as S10 did, made no difference and was taken out again. The counts are now alike: a scene's displayed pictures are the ones its GPU finished onto the slot, as a video's are its renderer's, and the window server's presented count is logged beside them (`presented=`). A covered or occluded scene can no longer set off recovery:

- drawn as usual under windows, it reads `healthy`: Lonely Cat, three checks on the final build, `displayed=61 expected=60 fed=61 asked=61 presented=4`, then `63 … presented=8` and `61 … presented=1`, each `verdict=healthy`;
- if the system stops calling its display link while the engine stands ready (the link up, the render thread answering within 250 ms, no more than three frames on the GPU), the count is `withheld` and the verdict `notComposited`: nothing is tried, the ladder does not climb, and no agent restart is asked for;
- only an engine that does not answer, a link that is gone, or a GPU that fails or falls behind climbs the ladder, as a stalled video does.

The rows are in `SceneClockTests` and `WatchdogSchedulingTests` ("a covered scene checked again and again never climbs, and never asks for an agent restart"). Whether the window server also presents a scene a few times a second with the desktop in view was not measured: the user's windows stayed where they were.

**Log lines**, new or changed:

- extension, `surface`: `scene: surface <S> draws <W> without: <note>; <note>…`, once after a load, listing what is stood in for or not drawn as the scene asks; `scene: surface <S> cannot load <W>, holding the poster: LivepaperScene.WallpaperEngineScene.LoadError 0: it has no programs (scene-programs.json): the app prepares them`; `… drawn by WallpaperEngineScene`.
- extension, `extension`: `extension: pointer read x=<x> y=<y> on display <x>,<y> <w>x<h>`, once a process.
- extension, `supervisor`: a scene's `check count … displayed=<n> expected=<m> fed=<f> asked=<a> presented=<p>`, and ` withheld` when it is.
- app, `app`: `scene: prepared <id>, <n> programs, <f> failed`; `scene: <id> not prepared: <reason>` (`.error`).

**Where a scene still differs from Wallpaper Engine.** Looked at against each item's `preview.*` (the four GIFs for motion); Wallpaper Engine itself is not on this Mac, so everything below is inferred from the items' files and those previews.

| Scene | Draws | Differs |
|---|---|---|
| Lonely Cat | The image, the water rippling around the cat, masked off it | Nothing seen against its still preview |
| Gaze | The image, the ripple on the water, fog and embers | Fog and ember glow are our textures. The preview is a still, so their motion is unchecked |
| A Lonely Winter | The background's flow, the three islands bobbing, snow, sakura petals, light shafts, smoke and fog | Petals, snow, shafts, smoke and fog are our textures; the petals are our shapes, white as in the preview. |
| Jet Lag | The cabin, the clouds scrolling past the window with motion blur and fisheye, dust motes, a light shaft | The window's pulse is audio-reactive and stays still. Its music is not heard while the wallpaper is muted. The dust motes do not move out of the pointer's way: their control point follows the pointer, which particles do not use yet |
| Backstreet Lofi | The street, reflections, the animated vending-machine screen, five pulses, motion blur, rain and splashes, hue shift, scan lines, god rays, bloom | The visualiser bars on the blue machine are flat, since audio-reactive input is silent; the preview shows them moving. The video screen (an MP4 texture) is on a screen the default property does not show, and is not decoded. Rain and splashes are our textures; perspective rain is drawn flat. The dust motes do not move out of the pointer's way |
| Agamemnon | The background with depth parallax, the puppet swaying, water waves, film grain, the vignette, ash, fog and light shafts | Parallax follows the pointer by an inferred formula. Ash, fog and shafts are our textures |
| All | | Scripts are not run (their stored values are used). Audio-reactive uniforms hear silence. Text, lights and 3D models are not drawn, nor particle emitters, initialisers, operators and renderers outside S9's set (`ParticleSystem.understood`), nor a video used as a texture; each is named in the `draws … without:` line. Wallpaper Engine's own textures are our stand-ins. Particle control points do not follow the pointer. User properties keep the item's defaults. A scene is drawn at 30 fps whatever it or Wallpaper Engine would choose, with no crossfade into or out of it. Blend-mode numbering, an effect pass's `compose`, the camera's `center` and `eye` offsets, the size a layer's effects run at (the layer's, here), and render-target formats are as S9 guessed them (`Spikes/results/S9.md`, open questions) |

**The checks, 2026-09-23, on this MacBook's display, under the user's windows, pointer and keyboard untouched** (the Library window was driven by Accessibility presses):

| # | Check | Result |
|---|---|---|
| 1 | Install the build; the app prepares the six scenes | Pass: six `scene: prepared` lines 8.6 s after launch, then the agent restart |
| 2 | Each scene set in turn from the Library's inspector | Pass for all six on the build before the last (A Lonely Winter and Agamemnon again on the last, whose particle colours changed): `loaded … drawn by WallpaperEngineScene`, the first picture 31 to 65 ms after the start, `shows … in the Metal slot`; window captures a second apart differed in 0.7 % (Jet Lag, slow clouds) to 73 % (Agamemnon, film grain) of their pixels; each capture looked at against the preview (table above) |
| 3 | The watchdog on a scene under the user's windows | Pass on the last build: `healthy`, 61 to 63 of 60 displayed, 1 to 8 presented (Liveness). A covering fullscreen app was not tried: the pointer and the keyboard stayed untouched |
| 4 | The desktop left on Lonely Cat | Pass, set to Fill |
| 5 | The prototype Botanical (`14F5E54A`) deleted through the inspector's Delete | Pass: `app: deleted wallpaper 14F5E54A-… "Botanical", undo offered`; its folder went to the Trash when the undo ended |

**Not checked yet.** The pointer and the keyboard stayed untouched and the desktop stayed under the user's windows, so these wait for a check on screen, the first four for the user:

- A fullscreen app covering a scene, and leaving: `pause.desktopCovered`, the link stopped, then resumed from where it stopped.
- A scene on the lock screen and in System Settings' Wallpaper preview, and across sleep and wake with the lid (S10 did not run cover, sleep or wake with Metal either).
- A scene's sound heard: Jet Lag's music or Backstreet Lofi's storm with the wallpaper's volume up.
- Agamemnon's parallax with the pointer moving, against Wallpaper Engine's if a PC is at hand.
- The watchdog's count with the desktop in view, and whether the window server then presents a scene every frame.
- The decoder check of check 4: no decoder session in the extension while a scene shows.
- A scene on a second display, and two displays showing the same scene.

One agent restart was not planned: a `make build` run while the extension ran (to check lint fixes) ended the running extension at 23:15 (inferred from the timing; there is no crash report), and the app's ladder restarted WallpaperAgent 50 s later, 21 minutes after the one before. The memory's rule holds: after a build, unregister the DerivedData copy, and do not build while a check is under way.

### Stopped scenes and their posters

Found and fixed on 2026-09-24. With a scene on the desktop, the user chose Pause All and saw "a really shitty blurry version of this wallpaper": the scene was not paused, it was replaced by its poster. The log showed the path: `app: pause all, render state … stopped`, the supervisor's `decision=still`, `scene: surface … stopped drawing at 98.85 s (stop)`, `holding still`. The stopped render state (record 0003) is a hold-still, and `SurfacePlayer.holdStill` let the scene go, put `poster.heic` up and hid the Metal slot. That poster was the Workshop item's preview cut to the scene's shape: 250×141 for Backstreet Lofi and 1024×576 for Lonely Cat, stretched over a 3600×2338 display. Two changes, both kept to the seams M11 already had.

**A stopped scene keeps its own last picture.** A still of the scene up, when the slot has its picture, stops the display link and lets the scene go as a suspend does (`SceneEngine.suspend("still")`: drawing, textures and sounds released, the scene time kept), but leaves the slot showing its last drawable, the scene at the surface's size. The poster still goes on the layers under it, so whatever hides the slot later (another wallpaper, nothing) shows the poster and never the neutral colour. The player's state is `.still`, so the supervisor's mapping is unchanged: Resume All asks for `show`, which loads the scene again and starts from the scene time it stopped at, the slot up throughout, with no jump to 0 and no flash of the poster. A still of the scene in a new presentation lays the picture out anew (scaled until the scene draws again); a still of the scene before it has a picture, or of another wallpaper, is the old path: the slot hidden, the scene and its time forgotten. A per-display pause already stopped the link and kept the last picture, and a suspend kept it too; `SurfacePlayerTests+Stopping` pins all three, the resume from each (through `surfaceCalls`, as the supervisor makes them) with the slot never hidden, and what may follow a scene, playing or held still. On a layer on no screen the system calls a display link a few times and then withholds it, so the tests read the scene time the engine keeps rather than count pictures.

**A scene's poster is drawn from the scene** (`ScenePoster`, `LivepaperImport`). At import, once `ScenePreparation.prepare` has written the programs, the app draws the scene offscreen with the drawing it is given (`Importer(sceneDrawing:)`, `WallpaperEngineScene` in the app; tests use a drawing that paints one colour, on the GPU, never a Workshop file) and writes `poster.heic`:

- At the scene's own size with its longest side at most 3840 (the video poster has no cap of its own; 3840 is a 4K display's width, and brings Gaze's 6000×3375 to 3840×2160). A smaller scene is drawn at its size, never enlarged.
- At 10 s of scene time, after a second of pictures at 30 fps (from 9 s, each finished before the next, as the drawing's particle buffers expect). Looked at against renders at 0, 2, 5, 10, 20 and 30 s of the six samples, read from the library into scratch: A Lonely Winter's petals have spread by 5 s, Gaze's fog over the water only by about 10 s, and 10 s looks like 30 s in every scene while simulating a third of the steps (a drawing re-simulates at most the last half minute when time jumps). The lead-in is for effects that carry a picture from frame to frame: Backstreet Lofi's motion-blurred fan is a dark blot in a first picture and itself after a second.
- As HEIC at quality 0.85, written whole (encoded in memory, then an atomic write), its TIFF `Software` set to `ScenePoster.marker` (`Livepaper scene poster 1, translator 1`). That marker is how the app knows a poster was drawn, and from which translator's programs: nothing is added to the folder, it cannot disagree with the file it is in, and programs translated anew draw the poster anew.
- A scene that cannot be drawn (no programs yet, no GPU, a drawing that throws) gets the preview's poster as before, and the import's outcome says why (`ImportOutcome.importedScene(_, preparation:, poster:)`). A scene with no preview is now imported when it can be drawn.

At launch, after `ScenePreparation.refresh`, `ScenePoster.refresh` draws the poster of every scene whose programs are the current translator's and whose poster does not carry the marker (`needsDrawing`): one scene at a time, off the main actor, each written whole. A drawn poster is never drawn again; one that cannot be drawn is tried again at the next launch; bumping the marker's number redraws every poster once. The app's poster cache reads a poster again when it is rewritten (`WallpaperArt.posterChanged`, a revision in `PosterCache.Request`), keeping the earlier picture up until the new one is decoded, so the library and the popover show it without a relaunch.

Drawn from the library into scratch with this code, the six samples took 0.2 to 0.7 s each, load included, and made posters of 191 KB (Jet Lag, mostly dark) to 1.4 MB (Agamemnon, film grain), against 0.1 MB for Lonely Cat's preview cut. Each was looked at against the item's own preview: the scene itself, sharp, and for Lonely Cat a different picture from the preview, which is another crop of the artwork.

Which scenes need their programs or their poster is read from their files on a thread of its own, in one pass before the work (`needsPreparing`, `needsDrawing`), so neither refresh reads a file on the cooperative pool.

**On screen, 2026-09-24,** with the branch's build installed on the user's MacBook (macOS 27, one 3600×2338 display), driven by Accessibility presses, under the user's windows with "Desktop fully covered" switched off for the check and on again after:

- The first launch drew the six posters within 4.1 s: `scene: poster of … drawn from the scene, 3840x2160 at 10 s` for five, and `1920x1080` for Backstreet Lofi, whose poster had been 250×141. The final build, whose marker names the translator, drew them once more at its first launch (2.6 s), and none at the launch after.
- Pause All over Agamemnon: `decision … still`, `stopped drawing at 805.73 s (still)`, `holds … still on its last picture, at 805.73 s`, `holding still`. Resume All: `loaded … in 384 ms`, `drawing at 30 fps from 805.73 s`, and no `shows … in the Metal slot`. The card's own pause: `stopped drawing at 76.81 s (pause)`, then `drawing at 30 fps from 76.81 s`.
- Captures of the desktop's wallpaper window (by window id; not kept, being Workshop artwork): playing, two frames a second apart differed in 20.2 % of their pixels; after Pause All, two frames two seconds apart in 0.00 %; after Resume All, 20.4 % again. The variance of the Laplacian, a measure of sharpness, was 133.4 playing and 134.1 paused: the paused picture is the scene's own frame at the display's resolution, looked at side by side with a playing one.

Not checked on screen: Quit, then an extension restart while stopped, holding the drawn poster; the lock screen before a scene's first picture.
