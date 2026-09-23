# M4: import pipeline and the ffmpeg helper

Turn a source file the user provides into a wallpaper in the library: one optimised copy that loops without a gap, a poster and a hover preview. Lane C. See `docs/roadmap.md` (Import stages) and decision records 0002, 0005 and 0006.

## Rules

- Code goes in `LivepaperImport` (nonisolated) and `Helpers/ffmpeg/`. Models and the `Library` come from `LivepaperCore` (M2).
- The source file is never modified or moved. The library keeps only the optimised copy.
- ffmpeg runs as a separate process with a fixed argument list, no network, a time limit and a size limit. It never runs at playback time. It is built from source without GPL or non-free parts (record 0006).
- Every stage can be cancelled, and a cancelled or failed import leaves nothing behind.
- The planner and the WE parser are pure and table-tested first. Stages that touch AVFoundation are tested against fixture files.

## What the spike settled

- The library is `~/Library/Application Support/Livepaper/` (record 0002). Staging is `.staging/` inside it, so the final move is a rename on one volume.
- The engine reads the video track only, with `AVAssetReaderTrackOutput` and no output settings. Two things it found decide what "loops without a gap" means for a file:
  - The reader brackets the frames with marker buffers that carry no media (an edit-boundary marker first; drain, notification and empty-media markers last, the last one stamped with the track's duration). Treating any of them as a frame makes every loop one frame too long. Frames are the buffers with at least one sample.
  - The reader leaves PTS in media time and carries the edit list as a separate output time, and the display layer honours the output time. ffmpeg's usual B-frame edit list (first frame at media time 0.0667) made the first pass run two frames ahead of the rest and held the last picture for three frame durations at the first seam. The engine now stamps everything in output time, but a file with no edit list cannot have the problem at all.
  - The next pass continues at `end of last frame − PTS of first frame`. A file whose first frame is not at zero, whose frame durations are uneven, or whose track is longer than its frames, would stall at the seam. Normalising fixes the file; the validator proves it.

## Stages

| Stage | Does | Tested by |
|---|---|---|
| Discover | A file, a folder, or a Wallpaper Engine folder → candidate source files. WE folders are recognised by `project.json`; only `type: video` is accepted (record 0005), with the title and preview taken from the project | Table tests on `project.json` samples: video, scene, web, malformed, missing file, path escaping the folder |
| Fingerprint | SHA-256 of the source file, before any conversion; a match in the library ends the import as a duplicate | Fixture pair with identical bytes and different names |
| Probe | Container, codec, size, frame rate (constant or variable), duration of each track, edit list, transfer function (HDR or not), rotation | Fixture corpus |
| Plan | Pure: probe result → `remux` (already H.264/HEVC, SDR, constant rate, clean timing) / `transcode` with AVFoundation / `ffmpeg` then normalise (WebM, MKV, AVI, WMV, GIF) / `reject` with a reason the UI can show | Table tests: one row per combination that changes the answer |
| Convert | Runs the plan into `.staging/<id>/`. Progress as an `AsyncStream` | Fixture corpus; cancel mid-convert |
| Normalise | First frame at zero and a sync sample; no edit list; constant frame durations; track duration equal to the sum of its frames; the audio track trimmed to the video track, never the reverse; closed first GOP; HDR tone-mapped to SDR | Fixtures: audio longer than video, edit list, variable frame rate, B-frames with a start offset, HDR |
| Artefacts | Poster (first frame that is not black), hover preview (small, low rate, no audio). A colour-matched tint still only if record 0001 ends on the desktop-window host | Sizes and existence; poster skips a black lead-in |
| Validate | The loop-seam validator, below. A failure sends the file back through transcode once, then rejects | Every fixture passes after normalise; a deliberately broken file fails |
| Commit | Add to the `Library`, save the manifest, rename `.staging/<id>` into place. Manifest first on disk only after the rename succeeds | Kill between steps in a test double; no orphan folder, no manifest entry without files |

## Loop-seam validator

Reads the optimised copy exactly as the engine will (video track, `AVAssetReaderTrackOutput`, no output settings) and ignores buffers with no samples. Passes when:

1. The first frame's PTS is zero and it is a sync sample.
2. Sorted by PTS, every step between frames equals the frame duration, within one tick of the track's timescale.
3. The end of the last frame equals the track's duration, and the asset has no edit list.
4. So the seam step, `first PTS + loop length − last PTS`, is one frame duration.
5. No frame's decode depends on a frame before the first sync sample.

It reports the numbers, not just pass or fail, so an import failure can say what was wrong with the file.

## ffmpeg helper

`Helpers/ffmpeg/build.sh` with a pinned version and sha256, the configure flags (decoders and demuxers for the accepted inputs, the VideoToolbox HEVC encoder, no network, no GPL, no non-free), and the licence texts. A CI job builds it for arm64, runs it on the fixtures, and publishes the binary together with the exact source archive. `FFmpegTool` finds the bundled binary, or a replacement the user points it at (the LGPL's relinking requirement).

## Done when

- The fixture corpus imports correctly: audio longer than video, edit lists, variable frame rate, HDR, WebM, GIF, a Wallpaper Engine folder, duplicates.
- The validator finds no seam in any optimised copy. (While `Spikes/` still builds, its displayed-picture probe, `s2 … probe=2`, is a useful cross-check on a couple of them; it is throwaway code and not a requirement.)
- Cancelling at any stage leaves no residue in `.staging/`.
- CI publishes the ffmpeg artefact and its source.
- `make gen build test lint` is green.

## As built

What M4 found out or decided on the way, for whoever builds on it (M6, M7, M9).

- **Normalise is not a pass of its own.** Both writers, the remux and the transcode, write a normalised file: frames stamped by counting from zero, the movie's timescale set to the track's so that the track's duration is exact, the session ended where the frames end, the audio decoded over the video's range and written as AAC. The ffmpeg route is ffmpeg, probe, plan again, then one of the two. ffmpeg is asked for no B-frames and a constant rate, so its output is remuxed, not encoded twice.
- **Validate comes before artefacts.** A failed validation transcodes again, and the artefacts are made from the copy that is kept.
- **B-frames cannot be remuxed clean.** `AVAssetWriter` puts back the start-offset edit list for reordered frames (media time 1024/15360 to 0), the very thing the spike found. So reordered frames are a reason to transcode, and the transcode switches reordering off.
- **"No edit list" means no edit that does anything.** `AVAssetWriter` always writes one edit from zero over the whole track. The validator accepts a single edit that plays the media from zero, unscaled, to its end, and nothing else.
- **A variable frame rate is made constant by the importer, not by AVFoundation.** `AVAssetReaderVideoCompositionOutput` vends a frame only when the picture changes, even on a fixed grid. `ConstantRateResampler` holds a frame over the slots the next one leaves empty, at the rate of the shortest frame, 60 at most.
- **Nothing in the module blocks on Swift's own threads.** `copyNextSampleBuffer()` waits, and a batch of imports doing that on the cooperative pool takes every thread and never comes back (found by the tests, which run in parallel). Reading and writing run on threads of their own (`onOwnThread`).
- **ffmpeg's `-fs` is not the size limit.** It stops quietly and reports success with half a file. The helper's output is measured while it runs and once more after it exits.
- **The commit is rename, then manifest.** `ImportLibrary.insert` is the one writer of the manifest; if it throws, the folder goes again. A process killed between the two leaves a folder the manifest does not list, and `sweepInterruptedImports`, which the app is to call at launch, removes it together with whatever is in `.staging/`. It judges folders against the manifest on disk only, and touches none when that cannot be read.
- **No tint still**, since record 0001 ended on the extension host.
- **The hover preview is optional.** One that cannot be made or would not loop is left out and the wallpaper is imported without it.
- **A transcoded H.264 source is held to its own rate** (`CopyBitRate.swift`). At constant quality 0.75 the copy came out larger than its source, a Wallpaper Engine file's by 9–13% and an x264 file's by up to 80%, so an H.264 source whose rate is known is encoded at an average 95% of its video rate, no more than the remux it stands in for would keep: VideoToolbox ignores an average rate when a quality is set and starves the picture under a data-rate limit, needs look-ahead or the first two seconds of every loop come out soft, and overshoots by a few percent over minutes of footage (hence 95%) and by half or more on a clip of a few seconds (hence up to two more passes, the target scaled down by the miss). The Wallpaper Engine file's copy went from 293 MB to 259 MB against a 267 MB source, at VMAF 98.4 against 98.9. HEVC and other sources keep constant quality: the hardware encoder at an x265 file's own rate scores VMAF 92 where constant quality scores 99. The software encoder, which CI has, has no look-ahead and AVFoundation throws on it, so it is asked for only where the writer can apply it.
- **Not done here:** bundling the helper into the app (`FFmpegTool.locate(replacement:bundled:)` is ready for it; M6 or M9), publishing the helper as a Release rather than a workflow artefact (M9), AV1 (ffmpeg's own decoder needs hardware), and the spike's `probe=2` cross-check.

## Out of scope

Drag and drop, the Open panel, Services and the URL scheme (M6, M7). Downloading anything. Wallpaper Engine scenes and web items, permanently.
