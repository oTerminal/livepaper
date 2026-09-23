import CoreGraphics
import Foundation
import ImageIO
import Metal
import Testing
import UniformTypeIdentifiers
import LivepaperScene

struct PosterDriftTests {
    static let moments = stride(from: 0.0, through: 240, by: 0.25).map(\.self)

    static let shapes: [Row<(poster: Double, surface: Double), Void>] = [
        Row("a square poster on a wide surface, as a Workshop preview is", (1, 16.0 / 9), ()),
        Row("a wide poster on a wider surface", (16.0 / 9, 2.2), ()),
        Row("a wide poster on a taller surface", (16.0 / 9, 16.0 / 10), ()),
        Row("a tall poster", (9.0 / 16, 16.0 / 10), ()),
    ]

    @Test(arguments: shapes)
    func `the window never shows past the poster's edge, and has the surface's shape`(row: Row<(poster: Double, surface: Double), Void>) {
        for time in Self.moments {
            let window = PosterDrift.window(at: time, posterAspect: row.input.poster, surfaceAspect: row.input.surface)
            #expect(window.origin.x >= 0 && window.origin.y >= 0)
            #expect(window.origin.x + window.size.x <= 1.000_1 && window.origin.y + window.size.y <= 1.000_1)
            let shape = Double(window.size.x) * row.input.poster / (Double(window.size.y))
            #expect(abs(shape - row.input.surface) < 0.001)
        }
    }

    @Test func `it moves all the time, never by a jump`() {
        let windows = Self.moments.map { PosterDrift.window(at: $0, posterAspect: 1, surfaceAspect: 16.0 / 9) }
        for (earlier, later) in zip(windows, windows.dropFirst()) {
            let step = max(abs(later.origin.x - earlier.origin.x), abs(later.origin.y - earlier.origin.y))
            #expect(step > 0, "still between two quarter seconds")
            #expect(step < 0.02, "a jump")
        }
    }

    @Test func `the brightness pulses a little either side of the poster's own`() {
        let brightness = Self.moments.map { PosterDrift.window(at: $0, posterAspect: 1, surfaceAspect: 1).brightness }
        #expect(brightness.allSatisfy { $0 >= 0.97 && $0 <= 1.03 })
        #expect((brightness.max() ?? 0) - (brightness.min() ?? 0) > 0.05)
    }
}

/// On a GPU, when the machine has one.
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil))
final class PosterSceneTests {
    let folder: URL
    let device: any MTLDevice

    init() throws {
        folder = FileManager.default.temporaryDirectory
            .appending(path: "LivepaperSceneTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        device = try #require(MTLCreateSystemDefaultDevice())
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A poster that runs from black on the left to red on the right, so that any drift across it changes the middle.
    func writePoster(width: Int = 64, height: Int = 64) throws {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        for column in 0..<width {
            context.setFillColor(red: Double(column) / Double(width - 1), green: 0, blue: 0, alpha: 1)
            context.fill(CGRect(x: column, y: 0, width: 1, height: height))
        }
        let image = try #require(context.makeImage())
        let file = folder.appending(path: SceneFolder.poster)
        let destination = try #require(CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    /// The middle pixel of the picture drawn at `time`, as BGRA.
    func middle(of scene: PosterScene, at time: Double, width: Int = 32, height: Int = 18) throws -> [UInt8] {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: SceneFolder.pixelFormat, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let queue = try #require(device.makeCommandQueue())
        let buffer = try #require(queue.makeCommandBuffer())
        scene.resize(width: width, height: height)
        scene.draw(into: texture, on: buffer, at: time)
        buffer.commit()
        buffer.waitUntilCompleted()
        var pixel = [UInt8](repeating: 0, count: 4)
        texture.getBytes(&pixel, bytesPerRow: width * 4, from: MTLRegionMake2D(width / 2, height / 2, 1, 1), mipmapLevel: 0)
        return pixel
    }

    @Test func `draws the poster, and a moment later a different part of it`() throws {
        try writePoster()
        let scene = try PosterScene(folder: folder, device: device)

        let first = try middle(of: scene, at: 0)
        let later = try middle(of: scene, at: 6)

        // Red, and only red, from somewhere in the middle of the poster.
        #expect(first[0] < 8 && first[1] < 8 && first[2] > 40 && first[2] < 215)
        #expect(first[2] != later[2])
    }

    @Test func `a folder with no poster cannot be drawn`() {
        #expect(throws: PosterScene.LoadError.noPoster(folder.appending(path: SceneFolder.poster))) {
            try PosterScene(folder: folder, device: device)
        }
    }
}
