# Formats AVFoundation cannot open are converted once by a bundled ffmpeg helper

AVFoundation cannot open WebM, MKV, AVI or WMV containers, and many Wallpaper Engine video items are WebM. At import, those files (and GIFs) are converted to HEVC by an ffmpeg binary shipped inside the app and run as a separate process. Playback never involves ffmpeg.

The binary is built from source in CI without GPL or non-free components and without network support, so it stays LGPL. Running it as a separate, replaceable executable, and publishing the build script and source, is what keeps an MIT app compatible with it.

## Considered options

- **The user's own ffmpeg, if installed.** No bundling, but WebM import would fail for most people with an instruction to install something.
- **libwebm + VideoToolbox, with libvpx and dav1d as fallbacks.** All BSD, smaller, but it covers WebM only and means owning a demux, decode and encode pipeline.
- **No WebM.** Loses a large share of Wallpaper Engine video items.
