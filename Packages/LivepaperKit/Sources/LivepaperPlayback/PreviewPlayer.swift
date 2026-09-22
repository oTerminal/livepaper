import AppKit
import AVFoundation
import LivepaperCore
import os

/// A wallpaper playing in a view, for the inspector and a tile's live preview (M6-screens.md):
/// one engine on one layer, laid out by a `Presentation` as a display would be.
///
/// It plays an optimised copy or a hover preview, and gives its decoder up whenever it cannot be
/// seen: hidden, or out of a window. Shown again, it starts again from the first frame. The one
/// `@MainActor` type in this module, since it is a view.
@MainActor
public final class PreviewPlayer: NSView {
    /// How the picture is fitted to the view.
    public var presentation: Presentation {
        didSet { if presentation != oldValue { applyLayout() } }
    }

    /// 0 to 1. At 0, the default, the audio track is not opened.
    public var volume = 0.0 {
        didSet {
            guard volume != oldValue else { return }
            let (engine, volume) = (engine, volume)
            Task { await engine.setVolume(volume) }
        }
    }

    /// What the view plays, or will once it can be seen.
    public private(set) var url: URL?

    private let videoLayer: AVSampleBufferDisplayLayer
    private let engine: LoopEngine
    private var videoSize: Size?
    private var isRunning = false
    /// Changes with every start and every release, so that a start that finishes late finds out.
    private var generation = 0

    /// `logger` is the app's own: the extension's lines go under its own subsystem.
    public init(logger: Logger, presentation: Presentation = Presentation()) {
        let videoLayer = AVSampleBufferDisplayLayer()
        // pictureRect gives the layer the picture's shape already, Stretch included.
        videoLayer.videoGravity = .resize
        videoLayer.opacity = 0
        self.videoLayer = videoLayer
        self.presentation = presentation
        engine = LoopEngine(feed: VideoLayerFeed(layer: videoLayer), logger: logger)
        super.init(frame: .zero)

        let host = CALayer()
        host.backgroundColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        host.masksToBounds = true
        host.addSublayer(videoLayer)
        layer = host
        wantsLayer = true
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        nil
    }

    // The renderer belongs to the layer, which goes with the view: the engine lets go of it first.
    deinit {
        let engine = engine
        Task { await engine.stop() }
    }

    /// Plays `url` from its first frame, in place of whatever played; at once if the view can be
    /// seen, otherwise once it can.
    public func play(_ url: URL) {
        guard url != self.url || !isRunning else { return }
        self.url = url
        if isShown { start(url) }
    }

    /// Stops and gives the decoder up.
    public func stop() {
        url = nil
        release()
    }

    /// Switches the displayed-picture probe on or off; while it is on, the engine logs the
    /// metrics line for the preview every `LoopEngine.metricsInterval` loops.
    public func setMetricsProbe(_ on: Bool) {
        let engine = engine
        Task { await engine.setMetricsProbe(on, subject: .preview) }
    }

    override public func layout() {
        super.layout()
        applyLayout()
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        visibilityChanged()
    }

    override public func viewDidHide() {
        super.viewDidHide()
        visibilityChanged()
    }

    override public func viewDidUnhide() {
        super.viewDidUnhide()
        visibilityChanged()
    }

    override public func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyLayout()
    }

    private var isShown: Bool {
        window != nil && !isHiddenOrHasHiddenAncestor
    }

    private func visibilityChanged() {
        if isShown {
            if let url, !isRunning { start(url) }
        } else {
            release()
        }
    }

    private func start(_ url: URL) {
        generation += 1
        let run = generation
        let fromNothing = !isRunning
        isRunning = true
        Task {
            let video = await engine.play(url)
            guard run == generation else { return }
            guard let video else {
                setOpacity(0)
                return
            }
            videoSize = video.size
            applyLayout()
            // From nothing the layer stays clear until it has a picture; a switch keeps the last one.
            if fromNothing {
                _ = await waitUntilReadyForDisplay(videoLayer)
                guard run == generation else { return }
            }
            setOpacity(1)
        }
    }

    private func release() {
        guard isRunning else { return }
        generation += 1
        isRunning = false
        setOpacity(0)
        let engine = engine
        Task { await engine.stop() }
    }

    private func setOpacity(_ opacity: Float) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.opacity = opacity
        CATransaction.commit()
    }

    private func applyLayout() {
        let scale = window?.backingScaleFactor ?? 2
        let geometry = SurfaceGeometry(size: Size(width: bounds.width, height: bounds.height), scale: scale)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = layerFrame(presentation: presentation, source: videoSize, surface: geometry)
        videoLayer.contentsScale = scale
        CATransaction.commit()
    }
}
