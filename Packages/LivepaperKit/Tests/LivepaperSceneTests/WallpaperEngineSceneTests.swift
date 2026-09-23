import Foundation
import Metal
import Testing
@testable import LivepaperScene
import LivepaperTestSupport

/// Drawing a scene offscreen, as the extension's scene engine drives it, and
/// reading back the pixels: layers where the scene puts them, over its clear
/// colour, in its order, a sprite sheet's frame by the time, a puppet posed.
/// The programs are written by hand in Metal as the translation would write
/// them (`SyntheticScene.imageProgramsJSON`), so these need a GPU and no tools.
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil))
final class WallpaperEngineSceneTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "livepaper-scene-\(UUID().uuidString)", directoryHint: .isDirectory)
    let device = MTLCreateSystemDefaultDevice()!

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    static let red = SyntheticScene.Colour(255, 0, 0)
    static let blue = SyntheticScene.Colour(0, 0, 255)

    /// A material of one translucent `genericimage2` pass drawing the texture `texture`.
    static func material(texture: String) -> String {
        #"{"passes": [{"shader": "genericimage2", "textures": ["\#(texture)"], "blending": "translucent"}]}"#
    }

    /// A 64 × 32 scene over a grey clear colour, of the layers given, each drawn from `material`.
    func scene(layers: [String], extra: [SyntheticScene.Entry] = [], programs: String? = SyntheticScene.imageProgramsJSON) throws -> URL {
        let entries = [
            SyntheticScene.Entry("scene.json", json: #"""
                {"general": {"clearcolor": "0.5 0.5 0.5", "orthogonalprojection": {"width": 64, "height": 32}},
                 "objects": [\#(layers.joined(separator: ", "))]}
                """#),
            SyntheticScene.Entry("models/red.json", json: #"{"material": "materials/red.json"}"#),
            SyntheticScene.Entry("models/blue.json", json: #"{"material": "materials/blue.json"}"#),
            SyntheticScene.Entry("materials/red.json", json: Self.material(texture: "red")),
            SyntheticScene.Entry("materials/blue.json", json: Self.material(texture: "blue")),
            SyntheticScene.Entry("materials/red.tex", SyntheticScene.solidTexture(Self.red, width: 4, height: 4)),
            SyntheticScene.Entry("materials/blue.tex", SyntheticScene.solidTexture(Self.blue, width: 4, height: 4)),
        ] + extra
        try SyntheticScene.writeFolder(at: folder, entries: entries, programs: programs)
        return folder
    }

    /// The picture at `time`, drawn at `width` × `height`, as BGRA bytes.
    func draw(_ scene: WallpaperEngineScene, width: Int = 64, height: Int = 32, at time: Double = 0) throws -> [UInt8] {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: SceneFolder.pixelFormat, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let target = try #require(device.makeTexture(descriptor: descriptor))
        let queue = try #require(device.makeCommandQueue())
        let buffer = try #require(queue.makeCommandBuffer())
        scene.resize(width: width, height: height)
        scene.draw(into: target, on: buffer, at: time)
        buffer.commit()
        buffer.waitUntilCompleted()
        #expect(buffer.error == nil)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        target.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixels
    }

    /// Red, green and blue at a pixel, from the top left.
    func colour(_ pixels: [UInt8], x: Int, y: Int, width: Int = 64) -> [UInt8] {
        let index = (y * width + x) * 4
        return [pixels[index + 2], pixels[index + 1], pixels[index]]
    }

    @Test func `draws a layer where the scene puts it, over the scene's clear colour`() throws {
        // The left half of the scene: y runs up from the bottom, as in Wallpaper Engine.
        let folder = try scene(layers: [SyntheticScene.layer(model: "models/red.json", origin: (16, 16), size: (32, 32))])

        let pixels = try draw(WallpaperEngineScene(folder: folder, device: device))

        #expect(colour(pixels, x: 8, y: 16) == [255, 0, 0])
        #expect(colour(pixels, x: 56, y: 16).allSatisfy { abs(Int($0) - 128) <= 2 })
    }

    @Test func `draws the scene's objects in order, later over earlier`() throws {
        let folder = try scene(layers: [
            SyntheticScene.layer(model: "models/red.json", origin: (32, 16), size: (64, 32)),
            SyntheticScene.layer(model: "models/blue.json", origin: (48, 16), size: (32, 32)),
        ])

        let pixels = try draw(WallpaperEngineScene(folder: folder, device: device))

        #expect(colour(pixels, x: 8, y: 16) == [255, 0, 0])
        #expect(colour(pixels, x: 56, y: 16) == [0, 0, 255])
    }

    @Test func `leaves out a layer that is not visible, and fades one by its alpha`() throws {
        let folder = try scene(layers: [
            SyntheticScene.layer(model: "models/red.json", origin: (16, 16), size: (32, 32), fields: ["visible": "false"]),
            SyntheticScene.layer(model: "models/blue.json", origin: (48, 16), size: (32, 32), fields: ["alpha": "0.5"]),
        ])

        let pixels = try draw(WallpaperEngineScene(folder: folder, device: device))

        #expect(colour(pixels, x: 8, y: 16).allSatisfy { abs(Int($0) - 128) <= 2 })
        let faded = colour(pixels, x: 56, y: 16)
        #expect(abs(Int(faded[0]) - 64) <= 3 && abs(Int(faded[2]) - 191) <= 3)
    }

    @Test func `covers an output of another shape, centred, cropping the longer way`() throws {
        // A 2:1 scene into a square: the middle square of it, so the red left quarter goes.
        let folder = try scene(layers: [SyntheticScene.layer(model: "models/red.json", origin: (8, 16), size: (16, 32))])

        let pixels = try draw(WallpaperEngineScene(folder: folder, device: device), width: 32, height: 32)

        #expect(colour(pixels, x: 1, y: 16, width: 32).allSatisfy { abs(Int($0) - 128) <= 2 })
    }

    @Test func `shows a sprite sheet's frame by the time`() throws {
        let sheet = SyntheticScene.spriteSheet([Self.red, Self.blue], tile: (4, 4), perImage: 2, seconds: 0.5, compressed: false)
        let folder = try scene(
            layers: [SyntheticScene.layer(model: "models/sheet.json", origin: (32, 16), size: (64, 32))],
            extra: [
                .init("models/sheet.json", json: #"{"material": "materials/sheet.json"}"#),
                .init("materials/sheet.json", json: #"{"passes": [{"shader": "genericimage2", "textures": ["sheet"]}]}"#),
                .init("materials/sheet.tex", sheet),
            ]
        )
        let drawing = try WallpaperEngineScene(folder: folder, device: device)

        #expect(colour(try draw(drawing, at: 0.25), x: 32, y: 16) == [255, 0, 0])
        #expect(colour(try draw(drawing, at: 0.75), x: 32, y: 16) == [0, 0, 255])
        #expect(colour(try draw(drawing, at: 1.25), x: 32, y: 16) == [255, 0, 0])
    }

    @Test func `draws the same picture for the same time, however it got there`() throws {
        let folder = try scene(layers: [SyntheticScene.layer(model: "models/red.json", origin: (16, 16), size: (32, 32))])
        let drawing = try WallpaperEngineScene(folder: folder, device: device)

        let first = try draw(drawing, at: 3)
        _ = try draw(drawing, at: 7)

        #expect(try draw(drawing, at: 3) == first)
    }

    @Test func `cannot load a scene that has no programs yet, so its surface holds its poster`() throws {
        let folder = try scene(layers: [SyntheticScene.layer(model: "models/red.json", origin: (16, 16), size: (32, 32))], programs: nil)

        #expect(throws: WallpaperEngineScene.LoadError.noPrograms(folder.appending(path: ScenePrograms.fileName))) {
            try WallpaperEngineScene(folder: folder, device: self.device)
        }
    }

    @Test func `cannot load a scene whose programs do not compile`() throws {
        let broken = SyntheticScene.imageProgramsJSON.replacingOccurrences(of: "vertex Out main0", with: "vertex Out main0 syntax error")
        let folder = try scene(layers: [SyntheticScene.layer(model: "models/red.json", origin: (16, 16), size: (32, 32))], programs: broken)

        #expect(throws: WallpaperEngineScene.LoadError.noProgramCompiles) {
            try WallpaperEngineScene(folder: folder, device: self.device)
        }
    }

    @Test func `tells what it could not draw, once each`() throws {
        let folder = try scene(layers: [
            SyntheticScene.layer(model: "models/red.json", origin: (16, 16), size: (32, 32)),
            #"{"id": 9, "name": "music", "sound": ["sounds/music.mp3"]}"#,
            #"{"id": 10, "name": "clock", "text": {"value": "12:00"}}"#,
        ])

        let drawing = try WallpaperEngineScene(folder: folder, device: device)
        _ = try draw(drawing)
        _ = try draw(drawing, at: 1)

        #expect(drawing.notes.filter { $0.contains("clock") }.count == 1)
    }
}
