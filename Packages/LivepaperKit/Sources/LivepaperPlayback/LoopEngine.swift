// The gapless loop (compressed samples straight from a reader into the layer's renderer, a second
// reader opened ahead, one ever-increasing timeline) is adapted from Phosphene's VideoRenderer.swift
// (MIT, (c) 2026 kageroumado, https://github.com/kageroumado/phosphene) by way of the spike's
// LoopEngine. See NOTICE at the repository root.

import AVFoundation
import LivepaperCore
import os
import QuartzCore
import Synchronization

/// One engine on one video layer: the gapless loop of `Spikes/results/S2.md`.
///
/// Readers take turns on the file, the next one opened while the current one is read, and their
/// compressed samples go straight into the layer's renderer, stamped onto one timeline that
/// only ever increases (`PassLedger`). The readers' calls block, so the engine is an actor whose
/// executor is its own serial queue: they run there and nowhere else, never on Swift's
/// cooperative pool. Nothing leaves the actor by callback: an owner asks and awaits the answer.
///
/// Engines come and go on a layer (`VideoLayerFeed`); each flushes what an earlier one left
/// before it enqueues anything.
public actor LoopEngine {
    public struct Video: Equatable, Sendable {
        public let url: URL
        /// The video track's natural size, in pixels.
        public let size: Size
        /// Seconds.
        public let frameDuration: Double
    }

    /// How long `pause()` and `resume()` take to bring the rate to 0 or back to 1. The picture
    /// is content, not interface (`docs/design/skill-mapping.md`), so the 300 ms rule does not apply.
    public static let rateRamp: Duration = .milliseconds(250)
    static let rateRampSteps = 10
    /// Loops between two metrics lines while the probe is on (spec, "Developer menu").
    public static let metricsInterval = 20
    /// Restarts in a row with no loop completed between them before the engine stops trying
    /// and leaves the next step to the watchdog.
    static let restartLimit = 3
    /// A flush that has not reported back by then is taken as done.
    static let flushTimeout = DispatchTimeInterval.seconds(1)

    let queue: DispatchSerialQueue
    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        queue.asUnownedSerialExecutor()
    }

    let feed: VideoLayerFeed
    let logger: Logger
    let probe: PictureProbe
    private let retired = Atomic(false)

    enum Lifecycle {
        case stopped
        case running
        /// Readers and decoder released; `resume()` starts again from a fresh reader.
        case suspended
    }

    var lifecycle = Lifecycle.stopped
    var isPaused = false
    var switches = SwitchCoalescer()
    /// Changes whenever what the engine is doing changes, so that the work of an earlier start
    /// finds out and stops.
    var generation = 0
    var startingRun: Int?
    var settleWaiters: [CheckedContinuation<Void, Never>] = []

    var media: LoopMedia?
    /// What the engine plays: set once its first frame is on the layer's queue.
    public internal(set) var video: Video?
    /// 0 to 1. At 0, the default, the audio track is not opened.
    public internal(set) var volume = 0.0
    var ledger = PassLedger(frameDuration: CMTime(value: 1, timescale: 30))
    var videoPass: ReaderPass?
    var audioPass: ReaderPass?
    var nextPass: ReaderPass?
    /// The audio reached the end of its pass before the video did, and waits for the video's seam.
    var audioWaitsForVideo = false
    var audioRenderer: AVSampleBufferAudioRenderer?
    var audioBroken = false
    var rampTask: Task<Void, Never>?
    var restartsWithoutLoop = 0

    var metricsSubject: PlaybackMetrics.Subject?
    var tally = EngineTally()

    public init(feed: VideoLayerFeed, logger: Logger) {
        queue = DispatchSerialQueue(label: "app.livepaper.playback.engine", qos: .userInitiated)
        self.feed = feed
        self.logger = logger
        probe = PictureProbe(feed: feed)
    }

    var renderer: AVSampleBufferVideoRenderer { feed.renderer }
    var synchroniser: AVSampleBufferRenderSynchronizer { feed.synchroniser }
    nonisolated var isRetired: Bool { retired.load(ordering: .sequentiallyConsistent) }

    /// Seconds a frame lasts, once a video plays.
    public var frameDuration: Double? { video?.frameDuration }

    // MARK: Playing

    /// Plays `url` from its first frame, on a fresh timeline from a fresh reader, or switches
    /// to it in place when something already plays. Returns once the video's first frame is on
    /// the layer's queue, with what then plays: nil when the file cannot be read.
    @discardableResult
    public func play(_ url: URL) async -> Video? {
        guard !isRetired else { return nil }
        switch lifecycle {
        case .stopped:
            lifecycle = .running
            isPaused = false
            switches = SwitchCoalescer()
            await request(url)
        case .suspended:
            switches.remember(url)
            await resume()
        case .running:
            await request(url)
        }
        await settled()
        return video
    }

    /// Switches in place (`Spikes/results/S7.md`): the last request wins, and requests that
    /// arrive while the renderer flushes become one restart. A request for the video already
    /// playing does nothing. While suspended the video is only remembered for `resume()`.
    @discardableResult
    public func `switch`(to url: URL) async -> Video? {
        guard !isRetired else { return nil }
        switch lifecycle {
        case .stopped:
            return await play(url)
        case .suspended:
            switches.remember(url)
            return nil
        case .running:
            await request(url)
            await settled()
            return video
        }
    }

    /// Stops advancing with a rate ramp, keeping the readers and the decoder.
    public func pause() {
        guard !isRetired, !isPaused else { return }
        isPaused = true
        guard lifecycle == .running else { return }
        probe.interruptGaps()
        ramp(to: 0)
    }

    /// Advances again after `pause()`, with a rate ramp, or after `suspend()`, from a fresh reader.
    public func resume() async {
        guard !isRetired else { return }
        let wasPaused = isPaused
        isPaused = false
        switch lifecycle {
        case .running:
            guard wasPaused else { return }
            probe.interruptGaps()
            ramp(to: 1)
        case .suspended:
            lifecycle = .running
            guard let url = switches.playing else { return }
            await start(url)
            await settled()
        case .stopped:
            return
        }
    }

    /// Stops advancing and releases the readers and the decoder's queue. The picture on screen
    /// stays where the renderer allows.
    public func suspend() async {
        guard !isRetired, lifecycle == .running else { return }
        generation += 1
        startingRun = nil
        lifecycle = .suspended
        if let latest = switches.wanted ?? switches.playing { switches.remember(latest) }
        haltFeeding()
        dropAudio()
        probe.interruptGaps()
        settleIfIdle()
        await flushRenderer(removingImage: false)
    }

    /// Releases everything and takes the picture off the layer, so that the layer reports it is
    /// not ready for display until an engine gives it another (S5).
    public func stop() async {
        guard !isRetired else { return }
        generation += 1
        startingRun = nil
        lifecycle = .stopped
        isPaused = false
        switches = SwitchCoalescer()
        haltFeeding()
        dropAudio()
        probe.interruptGaps()
        media = nil
        video = nil
        settleIfIdle()
        // Last, with nothing after it: a start that comes in meanwhile finds the rest done.
        await flushRenderer(removingImage: true)
    }

    /// Flushes and starts the video again from a fresh reader: the watchdog's first step, and
    /// what the engine does by itself when the renderer fails or asks for a flush.
    public func restart() async {
        guard !isRetired, lifecycle == .running else { return }
        if switches.handle(.flushBegan) == .flush {
            await flushAndStart()
        } else {
            await settled()
        }
    }

    /// Gives the layer up at once, even while a read blocks the engine's queue: the engine
    /// never touches the layer's renderer or clock again, and releases its own readers when it
    /// can. For a rebuild, where another engine takes the layer over.
    public nonisolated func retire() {
        retired.store(true, ordering: .sequentiallyConsistent)
        Task { await self.windDown() }
    }

    /// 0 to 1. Above 0 the audio track is read through the same reader into an audio renderer
    /// on the layer's synchroniser; at 0 it is not opened. Turning it on or off mid-pass takes
    /// effect at the next loop seam, whose reader is opened again for it; the level itself
    /// changes at once.
    public func setVolume(_ newValue: Double) {
        let level = newValue.isFinite ? min(max(newValue, 0), 1) : 0
        let wasAudible = volume > 0
        volume = level
        audioRenderer?.volume = Float(level)
        guard (level > 0) != wasAudible, lifecycle == .running, media != nil else { return }
        nextPass?.cancel()
        nextPass = nil
        let run = generation
        Task { await self.reopenNextPass(run) }
    }

    // MARK: Watching

    /// Counts the new pictures the layer shows over `window`, polling only for that window.
    /// Nil unless the engine is playing.
    public func displayedPictures(over window: Duration) async -> PictureCount? {
        guard !isRetired, lifecycle == .running, !isPaused, let video else { return nil }
        return await probe.count(over: window, frameDuration: video.frameDuration)
    }

    /// The picture on screen, drawn as `layout` says, at its surface's pixel size, in BGRA.
    public func snapshot(_ layout: SnapshotLayout) -> IOSurface? {
        guard !isRetired, let picture = renderer.displayedPixelBuffer(),
              let image = SnapshotCanvas.image(of: picture) else { return nil }
        return SnapshotCanvas.render(image, layout)
    }

    /// Switches the displayed-picture probe on or off. While it is on the engine logs the
    /// metrics line for `subject` every `metricsInterval` loops. Off by default: it polls.
    public func setMetricsProbe(_ on: Bool, subject: PlaybackMetrics.Subject) {
        metricsSubject = on ? subject : nil
        probe.measureGaps(frameDuration: on ? video?.frameDuration : nil)
    }

    /// The numbers the metrics line gives, since this video started on this engine; the
    /// presented gaps since the probe went on.
    public func metrics() -> PlaybackMetrics {
        var totals = tally
        totals.fold(ledger)
        let gaps = probe.gaps
        return PlaybackMetrics(
            video: EngineLog.name(of: video?.url),
            loops: totals.loops,
            seamsWatched: gaps?.seamsWatched ?? 0,
            largestSeamStep: totals.largestSeamStep,
            largestInLoopStep: totals.largestInLoopStep,
            largestPresentedGap: gaps?.largest,
            largestPresentedGapAtSeam: gaps?.largestAtSeam,
            gapsOverLimitAtSeams: gaps?.overLimitAtSeams ?? 0,
            gapsOverLimitElsewhere: gaps?.overLimitElsewhere ?? 0,
            smallestSeamLead: totals.smallestSeamLead,
            flushes: totals.flushes,
            failures: totals.failures,
            markerBuffersSkipped: totals.markersSkipped,
            nextReaderMisses: totals.nextReaderMisses
        )
    }
}
