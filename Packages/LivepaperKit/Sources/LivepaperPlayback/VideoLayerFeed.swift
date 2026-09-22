import AVFoundation

/// One video layer as its engines see it: the layer's video renderer, and the layer's
/// synchroniser, which clocks that renderer and, while the volume is up, the engine's audio.
///
/// Made once per layer, on the main actor where AVFoundation keeps the layer, and shared by the
/// engines that drive the layer in turn. The renderer stays on the one synchroniser for the
/// layer's life, so an engine that takes a layer over never has to wait for another to let go
/// of it.
///
/// `@unchecked Sendable` because AVFoundation does not mark the renderer Sendable. It holds
/// because the renderer is the layer's way to be fed from a background queue
/// (`sampleBufferRenderer`'s documentation): one engine's queue feeds it at a time, and the
/// probe's queue only asks it for the picture on screen, as the spike's probe did for all of S2.
public struct VideoLayerFeed: @unchecked Sendable {
    let renderer: AVSampleBufferVideoRenderer
    let synchroniser: AVSampleBufferRenderSynchronizer

    @MainActor
    public init(layer: AVSampleBufferDisplayLayer) {
        renderer = layer.sampleBufferRenderer
        synchroniser = AVSampleBufferRenderSynchronizer()
        // As the spike's bare timebase did: the first frame goes in with the clock stopped and
        // the clock starts when the engine says, not when the synchroniser thinks it has enough.
        synchroniser.delaysRateChangeUntilHasSufficientMediaData = false
        synchroniser.addRenderer(renderer)
    }
}
