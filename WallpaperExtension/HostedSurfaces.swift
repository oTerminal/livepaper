// One remote context per surface, kept by surface ID so that it outlives the agent's connection, with
// its layer tree set and flushed before the agent is answered, follows Phosphene's
// WallpaperXPCHandler.swift (MIT, (c) 2026 kageroumado, https://github.com/kageroumado/phosphene), by
// way of the spike's SurfaceStore. See NOTICE at the repository root.

import CoreGraphics
import Foundation
import LivepaperCore
import LivepaperPlayback
import QuartzCore
import WallpaperAgentBridge

/// One surface the extension hosts: the remote context WallpaperAgent shows,
/// the layer tree in it, and what the extension knows of where it is.
final class HostedSurface {
    let id: SurfaceID
    let context: RemoteContext
    let layers: SurfaceLayers
    private(set) var display: DisplayIdentity
    private(set) var isPreview: Bool
    /// What the layer tree is laid out for.
    var geometry: SurfaceGeometry
    /// The display's geometry as CoreGraphics last gave it, for the
    /// reconfiguration observer to compare with.
    var displayGeometry: SurfaceGeometry?
    /// As the supervisor's store has it: `.desktop` until the agent says otherwise.
    var mode = SurfacePresentationMode.desktop
    /// `false` once the agent has invalidated it, until it acquires it again.
    var isLive = true

    init(id: SurfaceID, context: RemoteContext, layers: SurfaceLayers, placement: SurfacePlacement, isPreview: Bool) {
        self.id = id
        self.context = context
        self.layers = layers
        display = placement.display
        self.isPreview = isPreview
        geometry = placement.geometry
        displayGeometry = placement.displayGeometry
    }

    /// The agent acquired it again, within its grace. The supervisor lays the
    /// tree out for the new geometry itself.
    func reacquired(at placement: SurfacePlacement, isPreview: Bool) {
        display = placement.display
        self.isPreview = isPreview
        geometry = placement.geometry
        displayGeometry = placement.displayGeometry
        isLive = true
    }
}

/// The surfaces the extension hosts, by surface ID. It mirrors the
/// supervisor's store, in the same turn of the main actor: a surface is added
/// when the supervisor makes one (`host`) and removed when it tears one down
/// (`tearDown`), so a surface here is one the supervisor knows.
final class HostedSurfaces {
    /// Whether the engines log the metrics line (`HostNotification.playbackMetrics`).
    private(set) var metricsProbe = false
    private var surfaces: [SurfaceID: HostedSurface] = [:]

    subscript(_ surface: SurfaceID) -> HostedSurface? {
        surfaces[surface]
    }

    /// The supervisor's `makeSurface`: the layer tree for a new surface, whole
    /// before it goes into `context`, and in the render server before the
    /// agent is answered.
    func host(_ surface: SurfaceID, in context: RemoteContext, at placement: SurfacePlacement, isPreview: Bool) -> SurfaceLayers {
        let layers = SurfaceLayers(
            id: surface,
            geometry: placement.geometry,
            logger: .surface,
            prepareVideoLayer: WallpaperAgentBridge.disallowDisplayCompositing
        )
        context.layer = layers.root
        CATransaction.flush()
        surfaces[surface] = HostedSurface(id: surface, context: context, layers: layers, placement: placement, isPreview: isPreview)
        if metricsProbe {
            Task { await layers.setMetricsProbe(true) }
        }
        return layers
    }

    /// The supervisor's `tearDown`: the agent let the surface go and did not
    /// take it back within the grace. Its context goes now; the supervisor then
    /// empties the layer tree with `showNothing()`, which is the tree's owner's
    /// obligation, and lets it go.
    func tearDown(_ surface: SurfaceID) {
        guard let hosted = surfaces.removeValue(forKey: surface) else { return }
        hosted.context.invalidate()
        ExtensionLog.notice(.contextInvalidated(surface, context: hosted.context.id))
    }

    /// The surface whose picture a snapshot hands back: the one asked for, or,
    /// when the agent's identifier is unknown, a live desktop surface, the
    /// main display's first.
    func snapshotSource(for surface: SurfaceID?) -> HostedSurface? {
        if let surface, let hosted = surfaces[surface] { return hosted }
        let main = Displays.identity(of: CGMainDisplayID())
        let desktops = surfaces.values.filter { $0.isLive && !$0.isPreview }.sorted { $0.id.description < $1.id.description }
        return desktops.first { $0.display == main } ?? desktops.first
    }

    /// The live desktop surfaces, by display: the ones the supervisor lays out
    /// again when a display's mode changes.
    func desktopSurfacesByDisplay() -> [DisplayIdentity: [HostedSurface]] {
        Dictionary(grouping: surfaces.values.filter { $0.isLive && !$0.isPreview }, by: \.display)
    }

    /// Switches the probe on every surface, and on those to come. `false` when
    /// it was already so.
    func setMetricsProbe(_ on: Bool) -> Bool {
        guard on != metricsProbe else { return false }
        metricsProbe = on
        for layers in surfaces.values.map(\.layers) {
            Task { await layers.setMetricsProbe(on) }
        }
        return true
    }
}
