// Throwaway spike code (docs/specs/M1-engine-spike.md). Never imported by the product.
//
// One CAContext per WallpaperID, contexts that outlive the agent's connection, and the
// grace period before teardown follow Phosphene's WallpaperXPCHandler.swift and
// WallpaperState.swift (MIT, (c) 2026 kageroumado). See Spikes/NOTICE.

import AppKit
import ColorSync
import Foundation

/// One hosted surface: a desktop Space, the lock screen, or the Settings preview.
final class HostedSurface {
    let id: UUID
    let context: CAContext
    let layers: SurfaceLayers
    let displayID: UInt32
    let displayUUID: String
    let isPreview: Bool
    var teardown: DispatchWorkItem?

    init(id: UUID, context: CAContext, layers: SurfaceLayers, displayID: UInt32, isPreview: Bool) {
        self.id = id
        self.context = context
        self.layers = layers
        self.displayID = displayID
        self.isPreview = isPreview
        // S3: the identity the product keys assignments by. Logged at every acquire so
        // stability across a replug can be read off the log.
        displayUUID = CGDisplayCreateUUIDFromDisplayID(displayID).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String } ?? "?"
    }
}

/// All surfaces of this extension process. Main thread only.
final class SurfaceStore {
    static let shared = SurfaceStore()
    private var surfaces: [UUID: HostedSurface] = [:]
    private var config = SpikeConfig()
    private var library = Spike.libraryA

    var generation: Int { config.generation }
    /// The engine playing on the desktop (not the Settings preview), if any.
    private var desktopEngine: LoopEngine? { surfaces.values.first { !$0.isPreview }?.layers.frontEngine }
    var frontLoops: Int { desktopEngine?.loops ?? 0 }

    func acquire(surfaceID: UUID, displayID: UInt32, size: CGSize, scale: CGFloat, isPreview: Bool, peer: Int32,
                 reply: @escaping (Any?, (any Error)?) -> Void) {
        reloadConfig()
        if let existing = surfaces[surfaceID] {
            existing.teardown?.cancel()
            existing.layers.layout(size: size, scale: scale)
            spikeLog("extension: ACQUIRE reuse surface \(surfaceID) ctx \(existing.context.contextId) display \(displayID) \(existing.displayUUID)")
            reply(PrivateBridge.remoteContextReply(contextID: existing.context.contextId), nil)
            apply(to: existing)
            return
        }

        let options: [String: Any] = displayID == 0 ? [:] : ["displayId": displayID]
        guard let context = CAContext.remoteContext(withOptions: options) as? CAContext, context.contextId != 0 else {
            spikeLog("extension: ACQUIRE failed, no remote CAContext")
            reply(nil, NSError(domain: "app.livepaper.spike", code: 1))
            return
        }
        let layers = SurfaceLayers(size: size, scale: scale)
        context.layer = layers.root
        CATransaction.flush()
        let surface = HostedSurface(id: surfaceID, context: context, layers: layers, displayID: displayID, isPreview: isPreview)
        surfaces[surfaceID] = surface
        spikeLog("extension: ACQUIRE new surface \(surfaceID) ctx \(context.contextId) display \(displayID) \(surface.displayUUID) size \(Int(size.width))x\(Int(size.height))@\(scale) preview \(isPreview) pid \(peer) (\(surfaces.count) surfaces)")

        // The agent starts hosting the context when it gets the reply. Reply once there
        // is something to show: at once for the colour, after the first frame for video,
        // and in any case within 2 s so an acquire can never hang.
        var replied = false
        let send = {
            guard !replied else { return }
            replied = true
            reply(PrivateBridge.remoteContextReply(contextID: context.contextId), nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: send)
        apply(to: surface, done: send)
    }

    func invalidate(surfaceID: UUID?) {
        guard let surfaceID, let surface = surfaces[surfaceID] else {
            spikeLog("extension: INVALIDATE unknown surface")
            return
        }
        // A re-acquire within the grace period (sleep/wake, a Space revisit) cancels this.
        let work = DispatchWorkItem { [weak self] in
            surface.layers.showColour()
            surface.context.invalidate()
            self?.surfaces[surfaceID] = nil
            spikeLog("extension: torn down surface \(surfaceID) (\(self?.surfaces.count ?? 0) left)")
        }
        surface.teardown?.cancel()
        surface.teardown = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
        spikeLog("extension: INVALIDATE surface \(surfaceID) display \(surface.displayID), teardown in 15 s unless re-acquired")
    }

    /// App -> extension: the config changed.
    func applyConfig() {
        reloadConfig()
        surfaces.values.forEach { apply(to: $0) }
    }

    private func reloadConfig() {
        let candidates = [Spike.libraryA, Spike.libraryB].compactMap { url in SpikeConfig.load(from: url).map { (url, $0) } }
        guard let (url, latest) = candidates.max(by: { $0.1.generation < $1.1.generation }) else { return }
        if latest != config { spikeLog("extension: config generation \(latest.generation) mode \(latest.mode) video \(latest.video ?? "-") from \(url.path)") }
        config = latest
        library = url
    }

    private func apply(to surface: HostedSurface, done: (() -> Void)? = nil) {
        let name = config.perDisplay?[surface.displayUUID] ?? config.video
        guard config.mode == "video", let name else {
            surface.layers.showColour()
            done?()
            return
        }
        let url = library.appendingPathComponent(name)
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            spikeLog("extension: cannot read \(url.path), showing the colour")
            surface.layers.showColour()
            done?()
            return
        }
        let generation = config.generation
        // Only the desktop surface probes: one probe is enough and it costs CPU.
        surface.layers.probeDisplayedFrames = config.probe == true && !surface.isPreview
        surface.layers.show(url, crossfade: config.crossfade) {
            spikeLog("extension: surface \(surface.id) display \(surface.displayID) now on \(name) (generation \(generation))")
            done?()
        }
    }

    /// S4: is every playing surface really showing new pictures in the 2 s after a wake?
    func checkAdvancing(after event: String) {
        if surfaces.values.allSatisfy({ $0.layers.frontEngine == nil }) { spikeLog("s4: after \(event): no surface is playing video (\(surfaces.count) surfaces)") }
        for surface in surfaces.values {
            guard let engine = surface.layers.frontEngine else { continue }
            let clip = engine.playingURL.lastPathComponent
            engine.advanced(over: 2) { ok, changes in
                spikeLog("s4: after \(event): \(surface.isPreview ? "preview" : "desktop") surface \(surface.id) display \(surface.displayID) on \(clip) showed \(changes) new pictures in 2 s: \(ok ? "PASS" : "FAIL")")
            }
        }
    }

    func currentFrame(surfaceID: UUID?) -> IOSurface? {
        guard let surface = surfaceID.flatMap({ surfaces[$0] }) ?? surfaces.values.first(where: { !$0.isPreview }) else { return nil }
        let bounds = surface.layers.root.bounds.size, scale = surface.layers.root.contentsScale
        return surface.layers.frontEngine?.currentFrameSurface(width: Int(bounds.width * scale), height: Int(bounds.height * scale))
    }

    /// S2 inside the extension: called from the heartbeat; logs every 20th loop.
    private var lastLoggedLoops = 0
    func logLoopMetrics() {
        guard let engine = desktopEngine else { return }
        let loops = engine.loops
        guard loops >= lastLoggedLoops + 20 || loops < lastLoggedLoops else { return }
        lastLoggedLoops = loops
        engine.summary { spikeLog("s2: in extension: \($0)") }
    }
}
