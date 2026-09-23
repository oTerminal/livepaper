# M11: Wallpaper Engine scenes

Import Wallpaper Engine scene items and draw them live in the wallpaper extension with Metal, and import a GIF scene as an ordinary video wallpaper. Lanes A and C together, since the model, the importer and the engine all change. It is built before M7-system-integration.md, at the product owner's request. See record 0007 (scenes drawn live, a GIF scene made into video, web and application items still refused), 0002 (the library, and the extension's read-only access to it), 0001 (the render host, and the layer tree made before the context is hosted), `Spikes/results/S10.md` (a Metal layer and a display link inside the extension) and `CONTEXT.md`.

## Rules

- Code goes in `LivepaperCore` (the model), `LivepaperImport` (discovery and the scene stages), a new nonisolated target `LivepaperScene` in `LivepaperKit`, `LivepaperPlayback` (the Metal slot, `SceneEngine`, `SurfacePlayer`), `WallpaperExtension/` and `App/`. `LivepaperScene` holds the Wallpaper Engine formats the product needs, the GIF-scene rule, the `SceneDrawing` seam, `PosterScene` and `ScenePreparation`. `LivepaperImport` and `LivepaperPlayback` depend on it; it depends on neither.
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
| `poster.heic` | The preview's first frame, cut to the scene's shape, since a Workshop preview is square |
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
| Prepare (`ImportStage.prepare`, "Preparing the scene") | Copies the project, the package and the preview into `.staging/<id>/`, then runs `ScenePreparation.prepare(_:)` on the staged folder. The hook does nothing yet; S9's shader translation plugs in there | The staged files, the hook called once on the staged folder and what it writes committed, a hook that fails leaving no residue |
| Artefacts | The poster from the preview's first frame, cut to the scene's shape; the hover preview from a `preview.gif` | A square preview and a 16:9 scene give a 16:9 poster; a GIF preview gives `hover.mov` and a JPEG gives none |
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
| `SceneEngine` | `LivepaperPlayback` | Drives one Metal slot with `CAMetalDisplayLink` at 30 fps, on a render thread of its own. Draws the `SceneDrawing` at the scene time, which it keeps across pause and resume. Counts presented pictures for the watchdog (`displayedPictures(over:)`) and counts each committed frame as fed, so `judgeProgress` and `notComposited` read as they do for video |
| `SurfacePlayer` | `LivepaperPlayback` | What the supervisor drives per surface. A video goes to `SurfaceLayers` as before. For a scene it holds the poster on `SurfaceLayers` with the decoders released, shows the Metal slot and runs the scene engine. Pause keeps the scene loaded and stops the link; suspend also releases the scene; stop and hold-still release everything. On the recovery ladder, `.flush` restarts the link, `.rebuildSurface` makes a new one and `.rebuildPipeline` loads the scene again. It switches between a video and a scene in both directions |
| `SceneDrawing` | `LivepaperScene` | The renderer seam: load a scene from its folder in the library with a Metal device; draw into a texture on a command buffer at a scene time in seconds; resize. S9's renderer is ported behind it later |
| `PosterScene` | `LivepaperScene` | The one implementation until then. It draws the scene's poster, slowly panned, so that liveness can be seen on screen |
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
| Surface calls for a scene | `surfaceCalls` rows: a scene is mapped as a video is, video → scene and scene → video included. `SurfacePlayer` on a real layer tree with a drawing that draws nothing (on a GPU): play holds the poster and shows the slot; pause keeps the scene, suspend lets it go and resume loads it again; hold-still, nothing and a video hide the slot and release the scene; another scene replaces the one up; a scene that cannot be drawn holds its poster; the watchdog counts a playing scene and nothing of a paused one |
| Scene engine bookkeeping | `SceneClock`, pure: scene time advances only while running, holds across pause and resume, never runs backwards, and starts at zero after a reset. `SceneTally`: presented pictures and committed frames over a window, so a surface fed but not presented reads as `notComposited` |

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
- `SceneDrawing` has one implementation, `PosterScene`, and import calls `ScenePreparation.prepare(_:)`, ready for S9.
- An "As built" section, as M4-import.md's, records what was decided on the way and the exact wording of every new log line, for M7-system-integration.md, M8-hardening.md and the port of S9.

## Out of scope

The real renderer: reading `scene.json` to draw it, layers, effects, particles and puppets, which S9 brings (`Spikes/S9/`, `Spikes/results/S9.md`). Shader translation at import; the hook is there. Energy numbers, for scenes as for video (M8-hardening.md). Scene scripts, scenes that show the time or the date, and web and application items (record 0007). Audio in scenes. Unpacked scene folders without a package. A scene's user properties.

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
- The extension names the one implementation in `HostedSurfaces.host` (`drawingType: PosterScene.self`): porting S9 is that line and a new type. Its import-time work goes in `ScenePreparation.prepare(_:)`, which runs on the staged folder with the item's files in it; what it writes is committed with them, and a throw fails the import with nothing left behind. S9's `ProgramManifest` (`scene-programs.json` beside the item's files, `Spikes/results/S9.md`) fits there as it is.
- `PosterScene` draws the poster cut to the surface's shape, zoomed 1.08 to 1.12 and drifting on sines of 24, 31 and 40 s, with a brightness pulse of ±3 % every 5 s (`PosterDrift`, pure and tested).

### Model and import

- `Wallpaper.scene: WallpaperScene?` (`project`, `width`, `height`) and `kind`; `RenderState.Display.scene` the same. Both files are 1.1. A scene's `optimisedCopy` is its package, which an older build fails to play and so holds the poster. A video's JSON is what it was, `scene` absent. The one 1.0 test that wrote `"minor" : 0` into a string now writes the current minor, and "writes its schema version" reads 1.1.
- `ImportOutcome.importedScene(Wallpaper)` for a scene kept to be drawn (nothing to report of an optimised copy); a GIF scene is `imported(_, report)` like any video. `ImportError.scene(SceneReadError)` and `.sceneWithoutSize`, `SkipReason.noScenePackage`, `WallpaperEngineProjectError.runsCode`. `ImportStage.prepare` sits between `validate` and `artefacts`. The words are pinned in `ImportWordsTests`.
- A scene's name is its project's title, or its folder's name (the Workshop number) when it has none. Its details are the orthogonal size, 30 fps, no length, codec `scene` and the bytes of its folder; the inspector shows Kind, Resolution, Frame rate, Size and Imported (`Wallpaper.detailsShown`, Core). The inspector's preview plays a scene's `hover.mov` over the poster, or nothing.
- **The GIF-scene rule** (`readSceneOutline`) is stricter than "one image layer": exactly one object, an `image` and nothing else (`particle`, `sound`, `text`, `model`, `light`, `animationlayers`), no effects, visible as a plain `true`; its `size` the scene's and its `origin` the centre, with scale, angles, colour, alpha and brightness absent or plain identity (a value bound to a user property fails); no scene-wide bloom or camera shake; a model without a puppet; one material pass with a `genericimage*` shader and one texture. The texture must then read as a sprite sheet of two or more frames (`SpriteSheet`): raw RGBA8888 (LZ4 or not) or ImageIO-encoded, frames axis-aligned, inside their image and shown for a time. Anything else is drawn live, so a GIF scene imported with "Compressed (DXT5)" goes to the renderer.
- The frames go to ProRes 422 at the shortest frame's time on a 6000-tick clock (`spriteSheetRate`: 0.1 s is 600/6000, 60 fps at most), longer frames held by `ConstantRateResampler`, over the scene's clear colour; the planner then transcodes it as any ProRes file. Botanical's two atlases (7680×7560 and 5760×4320) decode to 330 MB for the length of the conversion, in the app.
- The poster is cut about its middle to the scene's shape (a 1024² preview gives 1024×576), so the still, the inspector and the focal-point editors line up with the scene. With no preview there is no poster, and the import fails (`ArtefactError.noPicture`).
- `LivepaperScene` depends on Core only. The package reader maps the file. Workshop JSON may start with a byte-order mark; a JSON `true` is told from a `1` by its CF type, since Swift's `as? Bool` takes both.

### Playback

- `SurfacePlayer` wraps `SurfaceLayers` and leaves it as it was; the extension's `makeSurface` returns it and `HostedSurface` keeps it. The Metal slot is `SurfaceTree.scene`, the tree's last sublayer, laid out by `layerFrame` from the scene's size, drawable at the frame's pixels (at most 16384 a side). Its device is set on the first load, so a surface that only plays video never touches Metal.
- A scene: the poster held on the layers (their decoders released), the slot hidden, the scene loaded, the link started, and the slot shown once the first picture is drawn (a command buffer completed), at most 1 s later. To a video: the link stopped, the video started on the layers under the slot's last picture, then the slot hidden and the scene released. Pause stops the link; suspend also drops the drawing and resume loads it again; hold-still, nothing and a video release it; the same scene with a new presentation is laid out in place. `.flush` and `.rebuildSurface` make a new link, `.rebuildPipeline` loads the scene again. There is no crossfade into or out of a scene: the poster or the last picture bridges the cut.
- `SceneEngine` runs every surface's link on one thread with its own run loop (`SceneRenderThread`), one device and one command queue (`SceneGPU`), `preferredFrameRateRange` pinned to 30 and `preferredFrameLatency` 2. Scene time (`SceneClock`) is the link's target time since the run's first frame, carried across pauses. The watchdog's `displayed` is drawables with a presented time, `fed` the frames committed (`SceneTally`).

### Log lines

The extension, category `surface`, `.notice` unless marked; `<S>` is the surface ID, `<W>` the wallpaper's folder, which is its ID:

- `scene: surface <S> loaded <W> in <n> ms, drawn by <type>`
- `scene: surface <S> cannot load <W>, holding the poster: <domain> <code>: <description>` (`.error`)
- `scene: surface <S> has no Metal device, holding the poster` (`.error`)
- `scene: surface <S> drawing at 30 fps from <t> s`
- `scene: surface <S> first picture drawn <n> ms after the start`
- `scene: surface <S> shows <W> in the Metal slot`, or `…, with no picture after 1 s`
- `scene: surface <S> stopped drawing at <t> s (<pause|suspend|stop|restart>)`

The supervisor's lines are M5's, unchanged: a scene's `now showing`, `decision`, `check count` and `check verdict` read as a video's.

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
