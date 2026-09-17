// Throwaway spike code (docs/specs/M1-engine-spike.md). Never imported by the product.
//
// S2: gapless loop with AVSampleBufferDisplayLayer fed by two AVAssetReaders.
// The technique (compressed samples straight from the reader, a preloaded second
// reader, and an ever-increasing timestamp offset so the layer never sees the
// timeline restart) is adapted from Phosphene's VideoRenderer.swift
// (MIT, (c) 2026 kageroumado, https://github.com/kageroumado/phosphene). See Spikes/NOTICE.

import AVFoundation
import CoreMedia
import QuartzCore
import IOSurface
import VideoToolbox

final class LoopEngine {
    struct Metrics: Codable {
        var clip = ""
        var loops = 0
        var framesEnqueued = 0
        var frameDuration = 0.0
        /// Output (edit-list-adjusted) PTS of the first frame. Zero for a well-formed file.
        var firstPTS = 0.0
        /// Largest PTS step across a seam, in frame durations. 1.0 is perfect.
        var maxSeamStep = 0.0
        /// Largest PTS step inside one pass of the file, in frame durations.
        var maxInLoopStep = 0.0
        /// Smallest lead (enqueued-until minus timebase-now) when the first sample
        /// of a new pass was enqueued, in seconds. Negative means the layer ran dry.
        var minSeamLead = Double.greatestFiniteMagnitude
        var nextReaderMisses = 0
        /// Marker buffers (no media data) that the reader vended and the engine left out.
        var markerBuffersSkipped = 0
        /// "strip": ResetDecoderBeforeDecoding removed from the first frame of every pass
        /// after the first. "keep": enqueued as the reader vends it.
        var decoderReset = "strip"
        /// Seconds the harness window was not visible. The window server throttles a
        /// covered window to about 1 fps, so the probe ignores those periods (and the
        /// half second after them) instead of reporting them as stalls.
        var occludedSeconds = 0.0
        /// Seams at which the probe was watching a visible window.
        var seamsObserved = 0
        var flushes = 0
        var failures = 0
        /// Probe results (only when `probeDisplayedFrames` is on): largest interval
        /// between two changes of the displayed pixel buffer, in frame durations.
        var probeSamples = 0
        var maxPresentedGap = 0.0
        var maxPresentedGapAtSeam = 0.0
        var presentedGapsOverLimit = 0
        /// First 40 over-limit gaps as [timebase seconds, gap in frame durations].
        var overLimit: [[Double]] = []
        /// Every displayed-frame change as [timebase seconds, ms since the previous change,
        /// picture number], capped at 1500 (about eight seams). The picture number is the order in which that exact
        /// picture was first seen (so pass 0 numbers the file's frames), or -1 when the
        /// content probe is off.
        var changes: [[Double]] = []
        /// From AVVideoPerformanceMetrics at the end of the run.
        var totalFrames = 0
        var droppedFrames = 0
        var corruptedFrames = 0
        var accumulatedFrameDelay = 0.0
    }

    let layer: AVSampleBufferDisplayLayer
    let timebase: CMTimebase
    private let renderer: AVSampleBufferVideoRenderer
    private let queue = DispatchQueue(label: "spike.loop-engine", qos: .userInitiated)

    // MARK: State owned by the engine queue

    private var asset: AVURLAsset
    private var track: AVAssetTrack?
    private var currentReader: AVAssetReader?
    private var currentOutput: AVAssetReaderTrackOutput?
    private var nextReader: AVAssetReader?
    private var nextOutput: AVAssetReaderTrackOutput?

    private var running = false
    private var flushInFlight = false
    private var restartPending = false

    /// Added to every timestamp of the current pass so PTS and DTS only ever increase.
    private var offset = CMTime.zero
    /// Highest end time enqueued so far (max, not last: B-frames arrive out of order).
    private var enqueuedUntil = CMTime.zero
    private var firstSamplePTS: CMTime?
    private var passPTS: [Double] = []
    private var lastPassMaxPTS: Double?
    /// Host time at which each seam's first frame is due on screen.
    private var seamTimes: [Double] = []
    private var observedSeams = Set<Int>()

    /// Written on the engine queue only; read elsewhere through `finalMetrics` / `loops`.
    private(set) var metrics = Metrics()
    /// Called on the engine queue after each completed pass.
    var onLoop: ((Int) -> Void)?

    // MARK: Set once, before start()

    /// A/B switch for the seam experiment. See `Metrics.decoderReset`.
    var stripDecoderReset = true
    /// Set by the window harness; the extension has no window to be covered.
    var isOccluded: (() -> Bool)?
    var probeDisplayedFrames = false
    /// Also identify each displayed picture by content (probe=2). Costs a pixel transfer per frame.
    var probeContent = false

    // MARK: State owned by the probe queue

    private var transfer: VTPixelTransferSession?
    private var thumbnail: CVPixelBuffer?
    private var pictureNumbers: [UInt64: Int] = [:]
    private var probeTimer: DispatchSourceTimer?
    private var lastDisplayedBuffer: UInt64?
    private var lastDisplayedChange: CFTimeInterval = 0
    private var visibleSince: CFTimeInterval = 0

    init(layer: AVSampleBufferDisplayLayer, url: URL) {
        self.layer = layer
        self.renderer = layer.sampleBufferRenderer
        self.asset = AVURLAsset(url: url)
        self.requestedURL = url
        var tb: CMTimebase?
        CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &tb)
        self.timebase = tb!
        CMTimebaseSetTime(timebase, time: .zero)
        CMTimebaseSetRate(timebase, rate: 0)
        layer.controlTimebase = timebase
        metrics.clip = url.lastPathComponent
    }

    func configure(stripDecoderReset strip: Bool) {
        stripDecoderReset = strip
        metrics.decoderReset = strip ? "strip" : "keep"
    }

    /// The last clip this engine was asked to play. Set synchronously by `switchTo`, so a
    /// caller comparing against it never sees a stale answer while a switch is queued.
    private(set) var requestedURL: URL
    /// The clip the engine queue is really feeding, for logs and checks.
    var playingURL: URL { queue.sync { asset.url } }
    var loops: Int { queue.sync { metrics.loops } }

    // MARK: - Control

    /// `onFirstFrame` fires once the first frame is enqueued and flushed to the
    /// render server, on every path, so a caller waiting on it cannot hang.
    func start(onFirstFrame: (() -> Void)? = nil) {
        queue.async { [self] in
            running = true
            // The layer may have belonged to an earlier engine (S5 reuses the two video
            // layers). Whatever that engine queued is stamped on its own timeline and
            // would surface later on this one.
            renderer.flush()
            guard beginFresh() else { onFirstFrame?(); return }
            CMTimebaseSetRate(timebase, rate: 1)
            onFirstFrame?()
            if probeDisplayedFrames { startProbe() }
            prepareNextReader()
            feed()
        }
    }

    /// Idempotent: the two video layers are shared between successive engines, and a late
    /// second stop() would otherwise cancel the feed of the engine that took the layer over.
    func stop() {
        queue.sync {
            guard running else { return }
            running = false
            probeTimer?.cancel()
            renderer.stopRequestingMediaData()
            currentReader?.cancelReading()
            nextReader?.cancelReading()
            CMTimebaseSetRate(timebase, rate: 0)
        }
    }

    /// S7: switch in place on the layer that is already hosted. Runs to completion in
    /// FIFO order on one queue, so the last request wins; the only asynchronous hop is
    /// the decoder flush, and switches that arrive during it are coalesced.
    func switchTo(_ url: URL, completion: (() -> Void)? = nil) {
        requestedURL = url
        queue.async { [self] in
            guard running else { completion?(); return }
            if asset.url != url {
                asset = AVURLAsset(url: url)
                track = nil
                metrics.clip = url.lastPathComponent
                restart()
            }
            completion?()
        }
    }

    /// S4: is playback really advancing? Counts how often the displayed picture changes
    /// over `interval`, which a running timebase alone would not prove. Passes when at
    /// least half of the expected frames showed up.
    func advanced(over interval: TimeInterval, _ reply: @escaping (Bool, Int) -> Void) {
        let started = CACurrentMediaTime()
        var last: UInt64?
        var changes = 0
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "spike.advance-check", qos: .userInteractive))
        timer.schedule(deadline: .now(), repeating: .milliseconds(8))
        timer.setEventHandler { [self] in
            if let buffer = renderer.displayedPixelBuffer() {
                let id = Self.fingerprint(buffer)
                if id != last {
                    if last != nil { changes += 1 } // the first sighting is not a change
                    last = id
                }
            }
            guard CACurrentMediaTime() - started >= interval else { return }
            timer.cancel()
            let expected = interval / max(metrics.frameDuration, 0.001)
            reply(Double(changes) >= expected / 2, changes)
        }
        timer.resume()
    }

    /// S6: the picture on screen right now, as a BGRA IOSurface for the agent's snapshot.
    func currentFrameSurface(width: Int, height: Int) -> IOSurface? {
        guard let displayed = renderer.displayedPixelBuffer() else { return nil }
        let attributes: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
        var target: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &target)
        var session: VTPixelTransferSession?
        VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &session)
        // Crop to fill, like the layer's resizeAspectFill, or the still would not line up
        // with the video it stands in for.
        if let session { VTSessionSetProperty(session, key: kVTPixelTransferPropertyKey_ScalingMode, value: kVTScalingMode_Trim) }
        guard let target, let session, VTPixelTransferSessionTransferImage(session, from: displayed, to: target) == noErr,
              let surface = CVPixelBufferGetIOSurface(target)?.takeUnretainedValue() else { return nil }
        return unsafeBitCast(surface, to: IOSurface.self)
    }

    /// A one-line summary for the extension's log, where there is no JSON to write.
    func summary(_ reply: @escaping (String) -> Void) {
        finalMetrics { m in
            reply(String(format: "%@: loops %d, max presented gap %.2f frames (at seam %.2f), over 1.5: %d, renderer dropped %d/%d, min seam lead %.2f s, markers skipped %d",
                         m.clip, m.loops, m.maxPresentedGap, m.maxPresentedGapAtSeam, m.presentedGapsOverLimit, m.droppedFrames, m.totalFrames, m.minSeamLead, m.markerBuffersSkipped))
        }
    }

    func finalMetrics(_ reply: @escaping (Metrics) -> Void) {
        renderer.loadVideoPerformanceMetrics { [self] perf in
            queue.async { [self] in
                if let perf {
                    metrics.totalFrames = perf.totalNumberOfFrames
                    metrics.droppedFrames = perf.numberOfDroppedFrames
                    metrics.corruptedFrames = perf.numberOfCorruptedFrames
                    metrics.accumulatedFrameDelay = perf.totalAccumulatedFrameDelay
                }
                reply(metrics)
            }
        }
    }

    // MARK: - Readers (engine queue only)

    private func loadTrack() -> AVAssetTrack? {
        if let track { return track }
        let sem = DispatchSemaphore(value: 0)
        var loaded: AVAssetTrack?
        asset.loadTracks(withMediaType: .video) { tracks, _ in loaded = tracks?.first; sem.signal() }
        sem.wait()
        track = loaded
        if let loaded {
            let sem2 = DispatchSemaphore(value: 0)
            var fps: Float = 30
            Task {
                fps = (try? await loaded.load(.nominalFrameRate)) ?? 30
                sem2.signal()
            }
            sem2.wait()
            metrics.frameDuration = 1.0 / Double(max(fps, 1))
        }
        return loaded
    }

    private func makeReader() -> (AVAssetReader, AVAssetReaderTrackOutput)? {
        guard let track = loadTrack(), let reader = try? AVAssetReader(asset: asset) else { return nil }
        // nil settings: compressed samples pass through, the layer decodes in hardware.
        // Only the video track is read, so an audio track that is longer than the
        // video cannot stretch the loop.
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        return (reader, output)
    }

    private func prepareNextReader() {
        queue.async { [self] in
            guard running, let (reader, output) = makeReader() else { return }
            reader.startReading()
            nextReader = reader
            nextOutput = output
        }
    }

    /// Starts a pass on a fresh timeline: the first frame is enqueued while the clock
    /// is stopped so it cannot be judged late.
    private func beginFresh() -> Bool {
        guard let (reader, output) = makeReader() else {
            spikeLog("engine: cannot read \(asset.url.lastPathComponent)")
            return false
        }
        reader.startReading()
        currentReader = reader
        currentOutput = output
        offset = .zero
        enqueuedUntil = .zero
        firstSamplePTS = nil
        lastPassMaxPTS = nil
        passPTS.removeAll()
        CMTimebaseSetTime(timebase, time: .zero)
        // The first buffer the reader vends is a marker, not a frame: skip to a real one.
        var first = output.copyNextSampleBuffer()
        while let candidate = first, CMSampleBufferGetNumSamples(candidate) == 0 {
            metrics.markerBuffersSkipped += 1
            first = output.copyNextSampleBuffer()
        }
        if let first {
            markDisplayImmediately(first)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            enqueue(first)
            CATransaction.commit()
            CATransaction.flush()
        }
        return true
    }

    private func restart() {
        if flushInFlight { restartPending = true; return }
        flushInFlight = true
        CMTimebaseSetRate(timebase, rate: 0)
        renderer.stopRequestingMediaData()
        currentReader?.cancelReading()
        nextReader?.cancelReading()
        nextReader = nil
        nextOutput = nil
        // Keep the displayed frame: the first new frame replaces it, so no black.
        renderer.flush(removingDisplayedImage: false) { [self] in
            queue.async { [self] in
                flushInFlight = false
                if restartPending { restartPending = false; restart(); return }
                guard running, beginFresh() else { return }
                CMTimebaseSetRate(timebase, rate: 1)
                prepareNextReader()
                feed()
            }
        }
    }

    private func swapToNextReader() {
        finishPass()
        if let nextReader, let nextOutput {
            currentReader = nextReader
            currentOutput = nextOutput
            self.nextReader = nil
            self.nextOutput = nil
        } else {
            metrics.nextReaderMisses += 1
            guard let (reader, output) = makeReader() else { return }
            reader.startReading()
            currentReader = reader
            currentOutput = output
        }
        prepareNextReader()
        feed()
    }

    private func finishPass() {
        // The next pass continues where this one ended. Subtracting the file's first
        // PTS matters: with an edit list the first sample is not at zero, and using
        // the end time alone would hold the last frame for that long at every seam.
        let first = firstSamplePTS ?? .zero
        offset = CMTimeSubtract(enqueuedUntil, first)

        let sorted = passPTS.sorted()
        let frame = metrics.frameDuration
        if frame > 0 {
            for (a, b) in zip(sorted, sorted.dropFirst()) {
                metrics.maxInLoopStep = max(metrics.maxInLoopStep, (b - a) / frame)
            }
        }
        lastPassMaxPTS = sorted.last
        passPTS.removeAll(keepingCapacity: true)
        metrics.loops += 1
        onLoop?(metrics.loops)
    }

    // MARK: - Feeding

    private func feed() {
        renderer.requestMediaDataWhenReady(on: queue) { [self] in
            guard running else { renderer.stopRequestingMediaData(); return }
            if renderer.status == .failed {
                metrics.failures += 1
                spikeLog("engine: renderer failed: \(renderer.error?.localizedDescription ?? "?")")
                renderer.stopRequestingMediaData()
                queue.async { [self] in restart() }
                return
            }
            if renderer.requiresFlushToResumeDecoding {
                // After a flush the decoder needs a sync frame, and the reader is somewhere
                // in the middle of a GOP: start the file again rather than feed it P-frames.
                metrics.flushes += 1
                renderer.stopRequestingMediaData()
                queue.async { [self] in restart() }
                return
            }
            while renderer.isReadyForMoreMediaData {
                guard let sample = currentOutput?.copyNextSampleBuffer() else {
                    // requestMediaDataWhenReady is not re-entrant: hop before swapping.
                    renderer.stopRequestingMediaData()
                    if currentReader?.status == .failed {
                        // nil also means "the reader broke". That is not a finished pass.
                        metrics.failures += 1
                        spikeLog("engine: reader failed: \(currentReader?.error?.localizedDescription ?? "?")")
                        queue.async { [self] in restart() }
                    } else {
                        queue.async { [self] in swapToNextReader() }
                    }
                    return
                }
                enqueue(sample)
            }
        }
    }

    private func enqueue(_ sample: CMSampleBuffer) {
        // AVAssetReader brackets the frames with marker buffers that carry no media: an
        // EditBoundary marker at the start, and DrainAfterDecoding, PostNotificationWhenConsumed
        // and an EmptyMedia + PermanentEmptyMedia marker (at PTS = duration) at the end.
        // Enqueued, the last one reads as "one more frame": every pass then starts a frame
        // late and the final picture is held for two frame durations at each seam.
        let rawPTS = CMSampleBufferGetOutputPresentationTimeStamp(sample)
        guard CMSampleBufferGetNumSamples(sample) > 0, CMSampleBufferGetDataBuffer(sample) != nil, rawPTS.isValid else {
            metrics.markerBuffersSkipped += 1
            return
        }
        if firstSamplePTS == nil {
            firstSamplePTS = rawPTS
            metrics.firstPTS = rawPTS.seconds
        }
        let shifted = shift(sample)
        let pts = CMSampleBufferGetPresentationTimeStamp(shifted)
        let duration = CMSampleBufferGetDuration(shifted)
        let end = CMTimeAdd(pts, duration.isValid && duration > .zero ? duration : CMTime(seconds: metrics.frameDuration, preferredTimescale: 600))

        if passPTS.isEmpty, let last = lastPassMaxPTS, metrics.frameDuration > 0 {
            // First sample of a new pass: this is the seam.
            metrics.maxSeamStep = max(metrics.maxSeamStep, (pts.seconds - last) / metrics.frameDuration)
            metrics.minSeamLead = min(metrics.minSeamLead, pts.seconds - CMTimebaseGetTime(timebase).seconds)
            seamTimes.append(CACurrentMediaTime() + (pts.seconds - CMTimebaseGetTime(timebase).seconds))
        }
        passPTS.append(pts.seconds)
        if end > enqueuedUntil { enqueuedUntil = end }
        metrics.framesEnqueued += 1
        renderer.enqueue(shifted)
    }

    /// Returns the sample stamped for the endless timeline: its edit-list-adjusted
    /// ("output") time plus this pass's offset. The copy shares the data buffer.
    ///
    /// The reader leaves PTS in media time and carries the edit list as a separate output
    /// time, and the layer honours the output time. A file whose first frame is at media
    /// time 0.0667 (ffmpeg's B-frame edit list) therefore played its first pass two frames
    /// earlier than the retimed copies of the later passes, and held the last picture for
    /// three frame durations at the first seam. Stamping every pass the same way removes it.
    private func shift(_ sample: CMSampleBuffer) -> CMSampleBuffer {
        let mediaPTS = CMSampleBufferGetPresentationTimeStamp(sample)
        let outputPTS = CMSampleBufferGetOutputPresentationTimeStamp(sample)
        let editShift = CMTimeSubtract(mediaPTS, outputPTS)
        guard offset > .zero || editShift != .zero else { return sample }
        let dts = CMSampleBufferGetDecodeTimeStamp(sample)
        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sample),
            presentationTimeStamp: CMTimeAdd(outputPTS, offset),
            decodeTimeStamp: dts.isValid ? CMTimeAdd(CMTimeSubtract(dts, editShift), offset) : .invalid)
        var copy: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: nil, sampleBuffer: sample, sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleBufferOut: &copy)
        guard let copy else { return sample }
        // The reader marks the first frame of every pass ResetDecoderBeforeDecoding. It
        // is the same stream starting again at an IDR, so a reset buys nothing, and it
        // lands while the previous pass's last frames may still be inside the decoder.
        if stripDecoderReset, offset > .zero { CMRemoveAttachment(copy, key: kCMSampleBufferAttachmentKey_ResetDecoderBeforeDecoding) }
        return copy
    }

    private func markDisplayImmediately(_ sample: CMSampleBuffer) {
        guard let array = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
              CFArrayGetCount(array) > 0 else { return }
        let dict = unsafeBitCast(CFArrayGetValueAtIndex(array, 0), to: CFMutableDictionary.self)
        CFDictionarySetValue(
            dict,
            Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
            Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
    }

    // MARK: - Displayed-frame probe

    /// The call hands back a fresh CVPixelBuffer object each time, so the object's
    /// identity says nothing. The IOSurface behind it does: a decoded frame keeps its
    /// surface while it is on screen, and the next frame comes from another one. (The
    /// pixels themselves cannot be read: the decoder's output is a compressed format.)
    private static func fingerprint(_ buffer: CVPixelBuffer) -> UInt64 {
        guard let surface = CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue() else { return 0 }
        return UInt64(IOSurfaceGetID(surface))
    }

    /// The decoder's output is a compressed pixel format that cannot be read directly,
    /// so scale it to a small BGRA buffer first and hash that. Probe queue only.
    private func pictureNumber(of buffer: CVPixelBuffer) -> Int {
        if transfer == nil {
            VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &transfer)
            CVPixelBufferCreate(nil, 96, 54, kCVPixelFormatType_32BGRA, nil, &thumbnail)
        }
        guard let transfer, let thumbnail, VTPixelTransferSessionTransferImage(transfer, from: buffer, to: thumbnail) == noErr else { return -2 }
        CVPixelBufferLockBaseAddress(thumbnail, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(thumbnail, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(thumbnail) else { return -2 }
        let count = CVPixelBufferGetBytesPerRow(thumbnail) * CVPixelBufferGetHeight(thumbnail)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for index in 0 ..< count { hash = (hash ^ UInt64(bytes[index] >> 2)) &* 0x100_0000_01b3 } // drop 2 bits of decode noise
        if let known = pictureNumbers[hash] { return known }
        pictureNumbers[hash] = pictureNumbers.count
        return pictureNumbers.count - 1
    }

    /// Polls the pixel buffer the layer reports as displayed and times its changes.
    /// This is the closest public measure of "presented frames"; it costs CPU, so
    /// energy runs leave it off.
    private func startProbe() {
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: DispatchQueue(label: "spike.probe", qos: .userInteractive))
        timer.schedule(deadline: .now() + 1, repeating: .milliseconds(4), leeway: .nanoseconds(0))
        timer.setEventHandler { [self] in
            let now = CACurrentMediaTime()
            if isOccluded?() == true {
                queue.async { [self] in metrics.occludedSeconds += 0.004 }
                lastDisplayedBuffer = nil
                lastDisplayedChange = 0
                visibleSince = 0
                return
            }
            if visibleSince == 0 { visibleSince = now }
            guard now - visibleSince > 0.5, let buffer = renderer.displayedPixelBuffer() else { return }
            let id = Self.fingerprint(buffer)
            defer { lastDisplayedBuffer = id }
            guard id != lastDisplayedBuffer else { return }
            let picture = probeContent ? pictureNumber(of: buffer) : -1
            if lastDisplayedBuffer != nil, lastDisplayedChange > 0, CMTimebaseGetRate(timebase) > 0 {
                let gap = (now - lastDisplayedChange) / max(metrics.frameDuration, 0.001)
                let previousChange = lastDisplayedChange
                let at = CMTimebaseGetTime(timebase).seconds
                let interval = (now - lastDisplayedChange) * 1000
                queue.async { [self] in
                    if metrics.changes.count < 1500 { metrics.changes.append([at, interval, Double(picture)]) }
                    metrics.probeSamples += 1
                    metrics.maxPresentedGap = max(metrics.maxPresentedGap, gap)
                    if gap > 1.5 {
                        metrics.presentedGapsOverLimit += 1
                        if metrics.overLimit.count < 40 { metrics.overLimit.append([at, gap]) }
                    }
                    // A gap belongs to a seam when the interval it covers contains the seam,
                    // however long the gap is (one frame of slack each side).
                    let slack = metrics.frameDuration
                    if let seam = seamTimes.firstIndex(where: { $0 > previousChange - slack && $0 < now + slack }) {
                        metrics.maxPresentedGapAtSeam = max(metrics.maxPresentedGapAtSeam, gap)
                        observedSeams.insert(seam)
                        metrics.seamsObserved = observedSeams.count
                    }
                }
            }
            lastDisplayedChange = now
        }
        probeTimer = timer
        timer.resume()
    }
}
