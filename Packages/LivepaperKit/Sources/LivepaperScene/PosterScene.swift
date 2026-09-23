import CoreGraphics
import Foundation
import ImageIO
import Metal

/// The stand-in behind the seam until spike S9's renderer is ported in: the
/// scene's poster, cut to the surface's shape and drifting slowly, a little
/// closer and further, a little brighter and darker, so that anyone looking can
/// tell the surface is live and not holding a still.
public final class PosterScene: SceneDrawing {
    public enum LoadError: Error, Equatable, Sendable {
        case noPoster(URL)
        case noTexture
    }

    private let pipeline: any MTLRenderPipelineState
    private let sampler: any MTLSamplerState
    private let poster: any MTLTexture
    private var targetAspect = 16.0 / 9

    public required init(folder: URL, device: any MTLDevice) throws {
        let file = folder.appending(path: SceneFolder.poster, directoryHint: .notDirectory)
        guard
            let source = CGImageSourceCreateWithURL(file as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { throw LoadError.noPoster(file) }
        poster = try Self.texture(of: image, on: device)

        let library = try device.makeLibrary(source: Self.shaders, options: nil)
        let pipeline = MTLRenderPipelineDescriptor()
        pipeline.label = "livepaper.poster-scene"
        pipeline.vertexFunction = library.makeFunction(name: "poster_vertex")
        pipeline.fragmentFunction = library.makeFunction(name: "poster_fragment")
        pipeline.colorAttachments[0].pixelFormat = SceneFolder.pixelFormat
        self.pipeline = try device.makeRenderPipelineState(descriptor: pipeline)

        let sampling = MTLSamplerDescriptor()
        sampling.minFilter = .linear
        sampling.magFilter = .linear
        sampling.sAddressMode = .clampToEdge
        sampling.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: sampling) else { throw LoadError.noTexture }
        self.sampler = sampler
    }

    public func resize(width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        targetAspect = Double(width) / Double(height)
    }

    public func draw(into texture: any MTLTexture, on commandBuffer: any MTLCommandBuffer, at time: Double) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let aspect = Double(poster.width) / Double(max(poster.height, 1))
        var window = PosterDrift.window(at: time, posterAspect: aspect, surfaceAspect: targetAspect)
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&window, length: MemoryLayout<PosterDrift.Window>.stride, index: 0)
        encoder.setFragmentBytes(&window, length: MemoryLayout<PosterDrift.Window>.stride, index: 0)
        encoder.setFragmentTexture(poster, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// Opaque BGRA, the drawable's own layout, so the fragment shader samples it as it is.
    private static func texture(of image: CGImage, on device: any MTLDevice) throws -> any MTLTexture {
        let (width, height) = (image.width, image.height)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        guard
            width > 0, height > 0,
            let texture = device.makeTexture(descriptor: descriptor),
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ),
            let pixels = context.data
        else { throw LoadError.noTexture }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: pixels, bytesPerRow: width * 4)
        return texture
    }

    private static let shaders = """
        #include <metal_stdlib>
        using namespace metal;

        struct Window { float2 origin; float2 size; float brightness; float unused; };
        struct Point { float4 position [[position]]; float2 uv; };

        // One triangle over the whole target; uv runs 0 to 1 across the window, from the top left.
        vertex Point poster_vertex(uint vid [[vertex_id]], constant Window &window [[buffer(0)]]) {
            float2 corner = float2(float((vid << 1) & 2), float(vid & 2));
            Point out;
            out.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);
            out.uv = window.origin + float2(corner.x, 1.0 - corner.y) * window.size;
            return out;
        }

        fragment float4 poster_fragment(Point in [[stage_in]], constant Window &window [[buffer(0)]],
                                        texture2d<float> poster [[texture(0)]], sampler linear [[sampler(0)]]) {
            return float4(poster.sample(linear, in.uv).rgb * window.brightness, 1.0);
        }
        """
}

/// Where the poster is seen from at a moment: a window onto it, in the
/// poster's unit coordinates from the top left, and a brightness. Pure, so
/// that the drift can be pinned by tests without a GPU.
public enum PosterDrift {
    public struct Window: Equatable, Sendable {
        public var origin: SIMD2<Float>
        public var size: SIMD2<Float>
        public var brightness: Float
        let unused: Float = 0
    }

    /// The poster fills the surface, cut to its shape and zoomed in a little
    /// further, so that it has room to drift without an edge coming into view.
    /// Every movement is a slow sine, so it never jumps, and the periods differ,
    /// so it does not visibly repeat.
    public static func window(at time: Double, posterAspect: Double, surfaceAspect: Double) -> Window {
        let turn = 2 * Double.pi
        // The part of the poster that fills the surface's shape.
        let fill = surfaceAspect > posterAspect
            ? SIMD2(1, posterAspect / surfaceAspect)
            : SIMD2(surfaceAspect / posterAspect, 1)
        let zoom = 1.08 + 0.04 * (0.5 - 0.5 * cos(turn * time / 40))
        let size = fill / zoom
        let room = (SIMD2(1, 1) - size) / 2
        let centre = SIMD2(0.5, 0.5) + room * 0.8 * SIMD2(sin(turn * time / 24), sin(turn * time / 31 + 1))
        return Window(
            origin: SIMD2<Float>(centre - size / 2),
            size: SIMD2<Float>(size),
            brightness: Float(1 + 0.03 * sin(turn * time / 5))
        )
    }
}
