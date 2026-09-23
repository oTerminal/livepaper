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
            if current.state == .suspended, await !engine.load(drawn.folder) {
                await cannotDraw(wallpaper)
                return
            }
            if current.state != .playing { engine.start() }
            scene?.state = .playing
            return
        }
        await startScene(wallpaper, drawn)
    }

    public func holdStill(poster wallpaper: SurfaceWallpaper) async {
        await layers.holdStill(poster: wallpaper)
        leaveScene()
    }

    public func showNothing() async {
        await layers.showNothing()
        leaveScene()
    }

    public func pause() async {
        guard let current = scene else { return await layers.pause() }
        guard current.state == .playing else { return }
        engine.pause()
        scene?.state = .paused
    }

    public func resume() async {
        guard let current = scene else { return await layers.resume() }
        guard current.state == .paused || current.state == .suspended else { return }
        if current.state == .suspended, let drawn = current.wallpaper.scene, await !engine.load(drawn.folder) {
            await cannotDraw(current.wallpaper)
            return
        }
        engine.start()
        scene?.state = .playing
    }

    public func suspend() async {
        guard let current = scene else { return await layers.suspend() }
        guard current.state == .playing || current.state == .paused else { return }
        engine.suspend()
        scene?.state = .suspended
    }

    public func recover(_ level: RecoveryLevel) async {
        guard let current = scene else { return await layers.recover(level) }
        guard current.state == .playing, let drawn = current.wallpaper.scene else { return }
        switch level {
        case .flush, .rebuildSurface:
            engine.restart()
        case .rebuildPipeline:
            engine.stop()
            guard await engine.load(drawn.folder) else { return await cannotDraw(current.wallpaper) }
            engine.start()
        case .restartAgent:
            // The app's, never the surface's.
            return
        }
    }

    public func displayedPictures(over window: Duration) async -> PictureCount? {
        guard let current = scene else { return await layers.displayedPictures(over: window) }
        guard current.state == .playing else { return nil }
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
        scene = (wallpaper, .playing)
        // Whatever the slot showed stays up until the poster is under it.
        await layers.holdStill(poster: wallpaper)
        engine.stop()
        layers.tree.transaction { layers.tree.showScene(false) }
        layOutScene()
        guard await engine.load(drawn.folder) else { return await cannotDraw(wallpaper) }
        // A later request for this surface has the last word.
        guard scene?.wallpaper == wallpaper else { return }
        engine.start()
        let drew = await engine.waitForFirstPicture()
        guard scene?.wallpaper == wallpaper, scene?.state == .playing else { return }
        layers.tree.transaction { layers.tree.showScene(true) }
        logger.notice("\(EngineLog.sceneShown(self.layers.id, drawn.folder, waited: drew), privacy: .public)")
    }

    /// A scene that cannot be drawn holds its poster, as a video that cannot be played does.
    private func cannotDraw(_ wallpaper: SurfaceWallpaper) async {
        leaveScene()
        await layers.holdStill(poster: wallpaper)
    }

    /// A video: from a scene, the scene's last picture stays over the layers until the video
    /// has one of its own, then the slot goes.
    private func showVideo(_ wallpaper: SurfaceWallpaper, crossfade: Bool) async {
        guard scene != nil else { return await layers.show(wallpaper, crossfade: crossfade) }
        engine.pause()
        scene = nil
        await layers.show(wallpaper, crossfade: false)
        leaveScene()
    }

    /// The slot hidden and the scene let go, once something else is up.
    private func leaveScene() {
        scene = nil
        layers.tree.transaction { layers.tree.showScene(false) }
        engine.stop()
    }

    private func layOutScene() {
        guard let current = scene, let drawn = current.wallpaper.scene else { return }
        let placement = PicturePlacement(presentation: current.wallpaper.presentation, size: drawn.size)
        layers.tree.transaction { layers.tree.layOutScene(placement, on: layers.geometry) }
    }
}
