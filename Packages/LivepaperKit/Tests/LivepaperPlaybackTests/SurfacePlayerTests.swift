import Foundation
import LivepaperCore
import LivepaperScene
import Metal
import os
import Synchronization
import Testing
@testable import LivepaperPlayback

/// A drawing that draws nothing and counts itself, by the folder it was made for, so that
/// tests running side by side do not see each other's.
final class CountedDrawing: SceneDrawing {
    static let made = Mutex<[URL: Int]>([:])
    static let alive = Mutex<[URL: Int]>([:])
    let folder: URL

    required init(folder: URL, device: any MTLDevice) throws {
        self.folder = folder
        Self.made.withLock { $0[folder, default: 0] += 1 }
        Self.alive.withLock { $0[folder, default: 0] += 1 }
    }

    deinit {
        Self.alive.withLock { $0[folder, default: 0] -= 1 }
    }

    func draw(into texture: any MTLTexture, on commandBuffer: any MTLCommandBuffer, at time: Double) {}
    func resize(width: Int, height: Int) {}
}

/// A drawing that refuses every scene.
final class RefusingDrawing: SceneDrawing {
    struct Refused: Error {}

    required init(folder: URL, device: any MTLDevice) throws {
        throw Refused()
    }

    func draw(into texture: any MTLTexture, on commandBuffer: any MTLCommandBuffer, at time: Double) {}
    func resize(width: Int, height: Int) {}
}

/// A surface's player on a real layer tree, with drawings that draw nothing: whether a scene
/// is up, playing, paused or let go, and the Metal slot shown or hidden accordingly. What it
/// looks like on the desktop is M11's on-screen check. Needs a GPU for the scene engine.
@MainActor
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct SurfacePlayerTests {
    static let geometry = SurfaceGeometry(size: Size(width: 800, height: 500), scale: 2)
    static let logger = Logger(subsystem: "app.livepaper.tests", category: "scene")

    func player(_ drawing: any SceneDrawing.Type = CountedDrawing.self) -> SurfacePlayer {
        let layers = SurfaceLayers(
            id: .numbered(Int.random(in: 1...999_999)), geometry: Self.geometry, logger: Self.logger,
            prepareVideoLayer: { _ in }
        )
        return SurfacePlayer(layers: layers, drawingType: drawing, logger: Self.logger)
    }

    /// A scene of its own folder, so that its drawings are counted apart from every other test's.
    func scene() -> SurfaceWallpaper {
        var wallpaper = SurfaceWallpaper.scene(3)
        wallpaper.scene?.folder = URL(filePath: "/tmp/livepaper-tests/\(UUID().uuidString)", directoryHint: .isDirectory)
        return wallpaper
    }

    func alive(_ wallpaper: SurfaceWallpaper) -> Int {
        CountedDrawing.alive.withLock { $0[wallpaper.scene?.folder ?? URL(filePath: "/"), default: 0] }
    }

    func made(_ wallpaper: SurfaceWallpaper) -> Int {
        CountedDrawing.made.withLock { $0[wallpaper.scene?.folder ?? URL(filePath: "/"), default: 0] }
    }

    /// A drawing let go may still be in the frame the render thread is on; that frame ends at once.
    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test func `a scene is drawn in the Metal slot over its poster`() async {
        let player = player()
        let scene = scene()

        await player.show(scene, crossfade: false)

        #expect(player.state == .playing)
        #expect(player.wallpaper == scene)
        #expect(player.layers.state == .still, "the poster is held under the slot, the video's decoders released")
        #expect(player.layers.tree.scene.opacity == 1)
        #expect(made(scene) == 1 && alive(scene) == 1)
        #expect(player.layers.tree.scene.drawableSize.width > 0)
    }

    @Test func `a scene pauses and resumes keeping what it loaded, and a suspend lets it go`() async {
        let player = player()
        let scene = scene()
        await player.show(scene, crossfade: false)

        await player.pause()
        #expect(player.state == .paused)
        #expect(alive(scene) == 1)
        await player.resume()
        #expect(player.state == .playing)
        #expect(made(scene) == 1)

        await player.suspend()
        #expect(player.state == .suspended)
        #expect(await eventually { alive(scene) == 0 })
        await player.resume()
        #expect(player.state == .playing)
        #expect(made(scene) == 2 && alive(scene) == 1)
        #expect(player.layers.tree.scene.opacity == 1, "the last picture stays up through all of it")
    }

    @Test func `the watchdog counts a playing scene, and nothing of a paused one`() async throws {
        let player = player()
        await player.show(scene(), crossfade: false)

        let count = try #require(await player.displayedPictures(over: .milliseconds(100)))
        #expect(count.expected == 3)
        await player.pause()
        #expect(await player.displayedPictures(over: .milliseconds(100)) == nil)
    }

    @Test func `a still, nothing, or a video after a scene hides the slot and lets the scene go`() async {
        let player = player()
        let scene = scene()

        await player.show(scene, crossfade: false)
        await player.holdStill(poster: scene)
        #expect(player.state == .still)
        #expect(player.layers.tree.scene.opacity == 0)
        #expect(await eventually { alive(scene) == 0 })

        await player.show(scene, crossfade: false)
        await player.showNothing()
        #expect(player.state == .nothing)
        #expect(player.layers.tree.scene.opacity == 0)

        await player.show(scene, crossfade: false)
        // A video that cannot be played holds its poster, as it always has; the scene is gone all the same.
        await player.show(.numbered(1), crossfade: true)
        #expect(player.wallpaper?.scene == nil)
        #expect(player.layers.tree.scene.opacity == 0)
        #expect(await eventually { alive(scene) == 0 })
    }

    @Test func `another scene replaces the one up, and the same one with a new presentation stays up`() async {
        let player = player()
        let first = scene()
        let second = scene()
        await player.show(first, crossfade: false)

        var fitted = first
        fitted.presentation = Presentation(fit: .fit)
        await player.show(fitted, crossfade: false)
        #expect(made(first) == 1)
        #expect(player.wallpaper == fitted)

        await player.show(second, crossfade: true)
        #expect(await eventually { alive(first) == 0 })
        #expect(made(second) == 1)
        #expect(player.wallpaper == second)
        #expect(player.state == .playing)
    }

    @Test func `a scene that cannot be drawn holds its poster`() async {
        let player = player(RefusingDrawing.self)

        await player.show(scene(), crossfade: false)

        #expect(player.state == .still)
        #expect(player.layers.tree.scene.opacity == 0)
    }
}
