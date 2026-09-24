# Wallpaper Engine scenes are drawn live in the extension; a GIF scene becomes video

Decided by the product owner on 2026-09-23. It supersedes record 0005, which stopped Wallpaper Engine support at video items.

Scenes are about 54% of the Workshop, against 41% video items (record 0005's figures). Record 0005 turned them away because drawing one means a renderer of our own. The product owner reversed that. Livepaper now imports scene items as well as video items, and the wallpaper extension draws a scene live with Metal, on the same surfaces a video plays on.

A scene is drawn live and not turned into a video at import because its particles, effects and timelines do not repeat on one period. Any stretch of it baked into a video ends in a loop seam, the defect the product is built against. S10 (`Spikes/results/S10.md`, macOS 27.0) ran a Metal loop inside the extension, which is what made drawing live possible:

- A `CAMetalLayer` put into the surface's layer tree before the context is hosted, at opacity 0, and revealed later by an opacity change, draws on the desktop (measured: a capture of the desktop's wallpaper window showed the shader). The rule Phosphene found for video layers holds for it too.
- `CAMetalDisplayLink` fires in the extension, which has no window (measured: the first callback 5 to 20 ms after each start, the first presented frame 55 to 115 ms after).
- A light load held 60 and 30 fps. A heavy one (20 full-resolution passes) held 30 but not 60, where it managed about 45 (measured, on a machine busy with a FaceTime call). So scenes are drawn at 30 fps.

The exception is a GIF scene, one made from Wallpaper Engine's GIF template. Its only content is one image layer with an animated sprite sheet, with no effects and no particles. Its frames are an exact loop, so the importer takes them out of the sprite sheet and makes an ordinary video wallpaper. That needs no renderer, and the loop-seam validator can check the result. A prototype on the product owner's sample (Workshop item 2987840102, "Botanical": 40 frames of 1920×1080 at 0.1 s, across two sprite-sheet atlases) passed the validator.

What stays out:

- Web and application items are still refused, because each runs code of its own around the clock. Record 0005's reason stands for them.
- A scene's scripts (SceneScript, JavaScript in the properties of `scene.json`) are ignored. The scene is drawn without them.
- Scenes that show the time or the date are not a goal.

Consequences:

- The surface's layer tree gets a Metal slot, made with the rest of the tree before the context is hosted (record 0001), and a scene is shown by an opacity change. The pause rules, the supervisor and the watchdog treat a scene as they treat a video. For a scene the watchdog counts the pictures its GPU finished onto the slot, as it counts a video's renderer's; a display link the system stops calling is a covered surface, never a stall (M11, "As built").
- A scene wallpaper keeps the item's own files in the library, because it is drawn from them: its project, its package and its preview. The `shaders/` folder is Wallpaper Engine's DirectX shader cache and is not kept. The manifest and `render-state.json` go to schema 1.1. For a scene the optimised copy names the package, so a Livepaper that knows only video fails to play it and holds the poster.
- What draws a scene sits behind a seam, `SceneDrawing`: spike S9's reader and drawing (`Spikes/S9/`), ported as `WallpaperEngineScene` in `LivepaperScene`. Translating the items' shaders to Metal is S9's too, ported into `LivepaperImport`: the app runs it at import and again when the translation changes, and writes `scene-programs.json` beside the item's files. The extension only compiles that Metal and never translates. A scene without programs holds its poster, still.
- Record 0005 said the shader headers scenes depend on ship with Wallpaper Engine, not with the item. That is still true, and S9 does not use them. The four headers it compiles the items' shaders against (`common.h`, `common_blending.h`, `common_blur.h`, `common_perspective.h`) and its base image and particle materials are each marked as written from scratch, inferred from how the items' own shaders use them. S9 translates with glslang and SPIRV-Cross, which the spike runs as Homebrew's command-line tools. The product ships its own builds of both and runs them as helper processes (record 0008).
- A scene's cost is GPU time, which `top`'s power score does not see (S10). Its energy is not measured here.

## Considered options

- **Bake a scene into a video at import.** It would reuse the video pipeline and cost nothing extra at playback, but a scene does not repeat on one period, so the video has a loop seam. Kept only for GIF scenes, whose frames do repeat.
- **Draw scenes in a window of our own.** Record 0001: no lock screen from a window, and G1 passed, so no window host is built.
- **Keep refusing scenes** (record 0005). This leaves more than half of the Workshop out. The product owner reversed it.
