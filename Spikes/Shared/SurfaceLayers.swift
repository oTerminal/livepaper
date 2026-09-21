// Throwaway spike code (docs/specs/M1-engine-spike.md). Never imported by the product.

import AVFoundation
import QuartzCore

/// The layer tree of one surface. Everything is created up front: a layer added to a
/// context after WallpaperAgent has started hosting it does not composite (a Phosphene
/// finding), so switches and crossfades reuse the two video layers that already exist.
///
///     root
///     ├── colour   (S0: solid colour; stays underneath as the "nothing to play" state)
///     ├── video[0] (always opacity 1 once it has played)
///     └── video[1] (opacity animates; above video[0])
///
/// Because video[0] never fades, a crossfade in either direction has no frame where
/// neither video is visible (S5).
final class SurfaceLayers {
    static let spikeColour = CGColor(red: 0.04, green: 0.52, blue: 0.89, alpha: 1)

    let root = CALayer()
    let colour = CALayer()
    let video: [AVSampleBufferDisplayLayer]
    private(set) var engines: [LoopEngine?] = [nil, nil]
    /// Index of the layer the user currently sees, or nil while only the colour shows.
    private(set) var front: Int?
    var probeDisplayedFrames = false
    var probeContent = false
    var stripDecoderReset = true
    var isOccluded: (() -> Bool)?

    init(size: CGSize, scale: CGFloat) {
        video = [AVSampleBufferDisplayLayer(), AVSampleBufferDisplayLayer()]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.frame = CGRect(origin: .zero, size: size)
        root.contentsScale = scale
        root.backgroundColor = Self.spikeColour
        colour.backgroundColor = Self.spikeColour
        root.addSublayer(colour)
        for layer in video {
            layer.videoGravity = .resizeAspectFill
            layer.isOpaque = true
            layer.opacity = 0
            disallowDisplayCompositing(layer)
            root.addSublayer(layer)
        }
        layout(size: size, scale: scale)
        CATransaction.commit()
    }

    func layout(size: CGSize, scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.frame = CGRect(origin: .zero, size: size)
        root.contentsScale = scale
        for layer in [colour] + video {
            layer.frame = root.bounds
            layer.contentsScale = scale
        }
        CATransaction.commit()
        CATransaction.flush()
    }

    var frontEngine: LoopEngine? { front.flatMap { engines[$0] } }

    func showColour() {
        engines.forEach { $0?.stop() }
        engines = [nil, nil]
        front = nil
        setOpacity(0, on: 0, animated: false)
        setOpacity(0, on: 1, animated: false)
    }

    /// Shows `url`. With `crossfade` the other layer starts the new video and the top
    /// layer's opacity animates once the new video has a frame; without it the front
    /// layer switches in place.
    func show(_ url: URL, crossfade: Bool, duration: CFTimeInterval = 1.0, done: (() -> Void)? = nil) {
        guard let shown = front, let current = engines[shown] else {
            // Nothing is showing yet. If a first engine is already starting (an acquire and a
            // config change can arrive together), redirect it instead of starting a second
            // one on the same layer.
            if let starting = engines[0] { starting.switchTo(url, completion: done); return }
            startEngine(on: 0, url: url) { [self] in
                setOpacity(1, on: 0, animated: false)
                front = 0
                done?()
            }
            return
        }
        if current.requestedURL == url { done?(); return }
        guard crossfade else { current.switchTo(url, completion: done); return }

        let back = 1 - shown
        engines[back]?.stop()
        startEngine(on: back, url: url) { [self] in
            if back == 1 {
                setOpacity(1, on: 1, animated: true, duration: duration) // new video fades in on top
            } else {
                setOpacity(1, on: 0, animated: false) // new video is underneath, already opaque
                setOpacity(0, on: 1, animated: true, duration: duration) // old video fades out
            }
            front = back
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.2) { [self] in
                current.stop()
                if engines[shown] === current { engines[shown] = nil }
                done?()
            }
        }
    }

    private func startEngine(on index: Int, url: URL, ready: @escaping () -> Void) {
        let engine = LoopEngine(layer: video[index], url: url)
        engine.probeDisplayedFrames = probeDisplayedFrames
        engine.probeContent = probeContent
        engine.configure(stripDecoderReset: stripDecoderReset)
        engine.isOccluded = isOccluded
        engines[index] = engine
        engine.start { [self] in DispatchQueue.main.async { self.whenReadyForDisplay(index, deadline: CACurrentMediaTime() + 1, ready) } }
    }

    /// "First frame enqueued" is not "first frame on the layer": decoding it takes a few
    /// tens of milliseconds, and a fade that starts in that window shows the colour
    /// through the old video. The layer says when it really has a picture.
    private func whenReadyForDisplay(_ index: Int, deadline: CFTimeInterval, _ ready: @escaping () -> Void) {
        if video[index].isReadyForDisplay { ready(); return }
        if CACurrentMediaTime() > deadline { spikeLog("layers: video[\(index)] not ready for display after 1 s, going ahead"); ready(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.004) { [self] in whenReadyForDisplay(index, deadline: deadline, ready) }
    }

    private func setOpacity(_ value: Float, on index: Int, animated: Bool, duration: CFTimeInterval = 1.0) {
        let layer = video[index]
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if animated {
            // An explicit animation runs in the render server, so it keeps going
            // inside a remote context without this process driving each frame.
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = layer.presentation()?.opacity ?? layer.opacity
            fade.toValue = value
            fade.duration = duration
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(fade, forKey: "spike.fade")
        }
        layer.opacity = value
        CATransaction.commit()
        CATransaction.flush()
    }
}

/// `-[AVSampleBufferDisplayLayer _setDisallowsVideoLayerDisplayCompositing:]`, which
/// stops an empty layer from painting opaque black before its first frame. Private;
/// found by Phosphene (MIT, see Spikes/NOTICE) in Apple's own wallpaper extensions.
/// A no-op if the selector goes away.
private func disallowDisplayCompositing(_ layer: CALayer) {
    let selector = NSSelectorFromString("_setDisallowsVideoLayerDisplayCompositing:")
    guard layer.responds(to: selector), let imp = class_getMethodImplementation(type(of: layer), selector) else { return }
    typealias Setter = @convention(c) (AnyObject, Selector, ObjCBool) -> Void
    unsafeBitCast(imp, to: Setter.self)(layer, selector, true)
}
