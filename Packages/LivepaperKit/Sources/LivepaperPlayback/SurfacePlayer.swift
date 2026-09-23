import Foundation
import LivepaperCore
import LivepaperScene
import os

/// What the supervisor drives on one surface: a video through `SurfaceLayers`,
/// exactly as before, or a scene through a `SceneEngine` in the tree's Metal
/// slot, chosen by the wallpaper's kind (record 0007).
///
/// A scene holds its poster on the layers, with their decoders released, and is
/// drawn over it; the Metal slot is shown once the scene's first picture is
/// drawn, and hidden only once whatever follows is up. So a switch between a
/// video and a scene is a cut, in either direction, with the poster or the last
/// picture in between and never the neutral colour. Pausing, suspending and
/// the recovery levels mean for a scene what they mean for a video; they come
/// from the same supervisor on the same decisions.
///
/// On its owner's actor, which in the extension is the main actor, as `SurfaceLayers` is.
public final class SurfacePlayer: SurfacePlayback {
    public let layers: SurfaceLayers
    let engine: SceneEngine
    private let logger: Logger
    /// The scene up, and what it is doing; nil while the layers play a video or hold a still.
    private var scene: (wallpaper: SurfaceWallpaper, state: SurfacePlaybackState)?
    /// Counts the requests that change what the scene engine does. Work that waited, on a load,
    /// a poster or a first picture, goes on only if none came meanwhile: a later request for
    /// this surface has the last word, and has set the engine and the scene as it wants them.
    private var epoch = 0
    /// The scene whose picture the Metal slot shows over the layers; nil while it is hidden.
    private var slotScene: SurfaceScene?

    /// `drawingType` is what draws a scene (`WallpaperEngineScene` in the extension); `pointer`
    /// where the pointer is over the surface's display, for a scene that follows it.
    public init(
        layers: SurfaceLayers, drawingType: any SceneDrawing.Type, logger: Logger, pointer: (@Sendable () -> SIMD2<Float>?)? = nil
    ) {
        self.layers = layers
        self.logger = logger
        engine = SceneEngine(surface: layers.id, layer: layers.tree.scene, drawingType: drawingType, logger: logger, pointer: pointer)
    }

    public var state: SurfacePlaybackState { scene?.state ?? layers.state }
    public var wallpaper: SurfaceWallpaper? { scene?.wallpaper ?? layers.wallpaper }

    // MARK: SurfacePlayback

    public func show(_ wallpaper: SurfaceWallpaper, crossfade: Bool) async {
        guard let drawn = wallpaper.scene else {
            await showVideo(wallpaper, crossfade: crossfade)
            return
        }
        engine.setVolume(wallpaper.volume)
        if let current = scene, current.wallpaper.scene == drawn {
            // The same scene: its presentation and volume change in place, and it plays on.
            scene?.wallpaper = wallpaper
            layOutScene()
            guard current.state != .playing else { return }
            scene?.state = .playing
            await startDrawing()
            return
        }
        await startScene(wallpaper, drawn)
    }

    public func holdStill(poster wallpaper: SurfaceWallpaper) async {
        let run = leaveScene()
        await layers.holdStill(poster: wallpaper)
        // The slot goes once the poster is under it, unless a scene has come back meanwhile.
        if run == epoch { hideSlot() }
    }

    public func showNothing() async {
        let run = leaveScene()
        await layers.showNothing()
        if run == epoch { hideSlot() }
    }

    public func pause() async {
        guard let current = scene else { return await layers.pause() }
        guard current.state == .playing else { return }
        epoch += 1
        engine.pause()
        scene?.state = .paused
    }

    public func resume() async {
        guard let current = scene else { return await layers.resume() }
        guard current.state == .paused || current.state == .suspended else { return }
        scene?.state = .playing
        await startDrawing()
    }

    public func suspend() async {
        guard let current = scene else { return await layers.suspend() }
        guard current.state == .playing || current.state == .paused else { return }
        epoch += 1
        engine.suspend()
        scene?.state = .suspended
    }

    public func recover(_ level: RecoveryLevel) async {
        guard let current = scene else { return await layers.recover(level) }
        guard current.state == .playing else { return }
        switch level {
        case .flush, .rebuildSurface:
            engine.restart()
        case .rebuildPipeline:
            engine.stop()
            await startDrawing()
        case .restartAgent:
            // The app's, never the surface's.
            return
        }
    }

    public func displayedPictures(over window: Duration) async -> PictureCount? {
        guard let current = scene else { return await layers.displayedPictures(over: window) }
        // A scene counts once it draws, not while it loads: a slow load is no stall.
        guard current.state == .playing, engine.isRunning else { return nil }
        return await engine.displayedPictures(over: window)
    }

    public func layout(surface geometry: SurfaceGeometry) {
        layers.layout(surface: geometry)
        layOutScene()
    }

    // MARK: Scenes

    /// From a video, a still, nothing or another scene: the poster goes up under the Metal
    /// slot, the scene loads and starts, and the slot is shown once it has a picture.
    private func startScene(_ wallpaper: SurfaceWallpaper, _ drawn: SurfaceScene) async {
        epoch += 1
        let run = epoch
        scene = (wallpaper, .playing)
        engine.stop()
        // Whatever the slot showed stays up, still, until the poster is under it.
        await layers.holdStill(poster: wallpaper)
        // The poster is under the slot now. Unless another wallpaper has taken the surface
        // meanwhile, the slot goes until this scene has a picture on it.
        let isStillThisScene = run == epoch || scene?.wallpaper.scene == drawn
        if isStillThisScene, slotScene != drawn { hideSlot() }
        guard run == epoch else { return }
        layOutScene()
        await startDrawing()
    }

    /// Draws the scene up: loads it first when the engine does not hold it, starts it, and
    /// shows the slot once it has a picture, if the slot is not up already.
    private func startDrawing() async {
        guard let drawn = scene?.wallpaper.scene else { return }
        epoch += 1
        let run = epoch
        if !engine.holds(drawn.folder) {
            let loaded = await engine.load(drawn.folder)
            // A later request for this surface has the last word.
            guard run == epoch, let wallpaper = scene?.wallpaper else { return }
            guard loaded else { return await cannotDraw(wallpaper) }
        }
        engine.start()
        guard slotScene != drawn else { return }
        let drew = await engine.waitForFirstPicture()
        guard run == epoch else { return }
        slotScene = drawn
        layers.tree.transaction { layers.tree.showScene(true) }
        logger.notice("\(EngineLog.sceneShown(self.layers.id, drawn.folder, waited: drew), privacy: .public)")
    }

    /// A scene that cannot be drawn holds its poster, as a video that cannot be played does.
    private func cannotDraw(_ wallpaper: SurfaceWallpaper) async {
        leaveScene()
        hideSlot()
        await layers.holdStill(poster: wallpaper)
    }

    /// A video: from a scene, the scene's last picture stays over the layers until the video
    /// has one of its own, then the slot goes.
    private func showVideo(_ wallpaper: SurfaceWallpaper, crossfade: Bool) async {
        guard scene != nil else { return await layers.show(wallpaper, crossfade: crossfade) }
        let run = leaveScene()
        await layers.show(wallpaper, crossfade: false)
        if run == epoch { hideSlot() }
    }

    /// The scene let go at once, and anything that waited for it with it; its last picture
    /// stays on the slot until the caller hides it, once something else is up.
    @discardableResult
    private func leaveScene() -> Int {
        epoch += 1
        scene = nil
        engine.stop()
        return epoch
    }

    private func hideSlot() {
        slotScene = nil
        layers.tree.transaction { layers.tree.showScene(false) }
    }

    private func layOutScene() {
        guard let current = scene, let drawn = current.wallpaper.scene else { return }
        let placement = PicturePlacement(presentation: current.wallpaper.presentation, size: drawn.size)
        layers.tree.transaction { layers.tree.layOutScene(placement, on: layers.geometry) }
    }
}
