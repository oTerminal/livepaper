// A layer tree made whole before the agent hosts it, with two video layers up front, follows the
// spike's SurfaceLayers and Phosphene's finding that a layer added to a hosted context does not
// composite (MIT, (c) 2026 kageroumado, https://github.com/kageroumado/phosphene). See NOTICE at the
// repository root.

import AVFoundation
import CoreGraphics
import ImageIO
import LivepaperCore
import QuartzCore

/// Where a picture goes: how it is fitted, and its size in pixels once known.
struct Placement: Equatable {
    var presentation: Presentation
    var size: Size?
}

/// The layers of one surface, and what is done to them, without the engines that play on them.
///
///     root     black behind a wallpaper, which is Fit's bars; the neutral colour with none
///     ├── still    the poster, laid out as its video would be
///     ├── lower    video, opaque once it has played
///     └── upper    video, the only layer whose opacity is ever animated
///
/// Changes go in a transaction without implicit animations and are pushed to the render server
/// at once: the tree lives in a remote context.
final class SurfaceTree {
    private static let barColour = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    private static let fadeKey = "livepaper.crossfade"

    let root = CALayer()
    private let still = CALayer()
    private let video: Slots<AVSampleBufferDisplayLayer>
    let feeds: Slots<VideoLayerFeed>

    init(prepareVideoLayer: @MainActor (AVSampleBufferDisplayLayer) -> Void) {
        let lower = AVSampleBufferDisplayLayer()
        let upper = AVSampleBufferDisplayLayer()
        video = Slots(lower: lower, upper: upper)
        feeds = Slots(lower: Self.feed(for: lower, prepareVideoLayer), upper: Self.feed(for: upper, prepareVideoLayer))

        transaction {
            root.masksToBounds = true
            root.backgroundColor = SurfaceLayers.neutralColour
            still.contentsGravity = .resize
            still.opacity = 0
            root.addSublayer(still)
            for layer in video.all {
                layer.isOpaque = true
                layer.opacity = 0
                root.addSublayer(layer)
            }
        }
    }

    private static func feed(
        for layer: AVSampleBufferDisplayLayer,
        _ prepareVideoLayer: @MainActor (AVSampleBufferDisplayLayer) -> Void
    ) -> VideoLayerFeed {
        onMainThread(layer) { layer in
            // pictureRect gives the layer the picture's shape already, Stretch included.
            layer.videoGravity = .resize
            prepareVideoLayer(layer)
            return VideoLayerFeed(layer: layer)
        }
    }

    func transaction(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
        CATransaction.flush()
    }

    /// Every layer by Core's `pictureRect`, so that the still and the video line up.
    func layOut(_ geometry: SurfaceGeometry, still stillPlacement: Placement?, video placements: Slots<Placement?>) {
        let scale = geometry.scale > 0 ? geometry.scale : 1
        root.frame = CGRect(x: 0, y: 0, width: geometry.size.width, height: geometry.size.height)
        root.contentsScale = scale
        still.frame = frame(for: stillPlacement, on: geometry)
        still.contentsScale = scale
        for slot in VideoSlot.allCases {
            video[slot].frame = frame(for: placements[slot], on: geometry)
            video[slot].contentsScale = scale
        }
    }

    private func frame(for placement: Placement?, on geometry: SurfaceGeometry) -> CGRect {
        layerFrame(presentation: placement?.presentation ?? Presentation(), source: placement?.size, surface: geometry)
    }

    /// Black behind a wallpaper, for Fit's bars; the neutral colour when there is none.
    func showBackground(behindWallpaper: Bool) {
        root.backgroundColor = behindWallpaper ? Self.barColour : SurfaceLayers.neutralColour
    }

    func showStill(_ image: CGImage?) {
        still.contents = image
        still.opacity = image == nil ? 0 : 1
    }

    func apply(_ changes: [OpacityChange]) {
        for change in changes {
            video[change.slot].removeAnimation(forKey: Self.fadeKey)
            video[change.slot].opacity = change.opacity
        }
    }

    /// An explicit animation runs in the render server, so it keeps going inside a remote
    /// context without this process driving each frame (S5).
    func animate(_ change: OpacityChange, over duration: Duration) {
        let layer = video[change.slot]
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.presentation()?.opacity ?? layer.opacity
        fade.toValue = change.opacity
        fade.duration = duration / .seconds(1)
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(fade, forKey: Self.fadeKey)
        layer.opacity = change.opacity
    }

    func hideVideo() {
        apply(VideoSlot.allCases.map { OpacityChange($0, 0) })
    }

    /// Stops any fade under way where it is headed.
    func stopFades() {
        for layer in video.all { layer.removeAnimation(forKey: Self.fadeKey) }
    }

    /// Whether the layer got a picture before the bounded wait ran out.
    func waitUntilReady(_ slot: VideoSlot) async -> Bool {
        await waitUntilReadyForDisplay(video[slot])
    }
}

/// Decoded here, off the owner's actor, and at once rather than when first drawn.
@concurrent
func loadPoster(_ url: URL) async -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
}

@concurrent
func renderPoster(_ image: CGImage, _ layout: SnapshotLayout) async -> IOSurface? {
    SnapshotCanvas.render(image, layout)
}
