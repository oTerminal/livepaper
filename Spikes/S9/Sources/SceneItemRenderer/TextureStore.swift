import Foundation
import Metal
import SceneItemFormat

/// A texture on the GPU: one MTLTexture per image (a sprite sheet can span several).
public final class GPUTexture {
    public let textures: [any MTLTexture]
    /// (texture width, texture height, image width, image height): what g_TextureNResolution carries.
    public let resolution: SIMD4<Float>
    public let frames: [TexFile.Frame]
    public let pointFiltered: Bool
    public let clamp: Bool

    init(textures: [any MTLTexture], resolution: SIMD4<Float>, frames: [TexFile.Frame] = [],
         pointFiltered: Bool = false, clamp: Bool = true) {
        self.textures = textures
        self.resolution = resolution
        self.frames = frames
        self.pointFiltered = pointFiltered
        self.clamp = clamp
    }

    var duration: Float { frames.reduce(0) { $0 + $1.seconds } }

    /// The image and UV rect to draw at `time`: the current sprite-sheet frame, or the image inside its
    /// (possibly padded) texture.
    func frame(at time: Float) -> (texture: any MTLTexture, rect: SIMD4<Float>) {
        guard !frames.isEmpty, duration > 0 else {
            return (textures[0], SIMD4(0, 0, resolution.z / resolution.x, resolution.w / resolution.y))
        }
        var t = time.truncatingRemainder(dividingBy: duration)
        var chosen = frames[frames.count - 1]
        for f in frames {
            if t < f.seconds { chosen = f; break }
            t -= f.seconds
        }
        let tex = textures[min(chosen.image, textures.count - 1)]
        let w = Float(tex.width), h = Float(tex.height)
        return (tex, SIMD4(chosen.x / w, chosen.y / h, chosen.ux / w, chosen.vy / h))
    }
}

/// Loads an item's textures (all at load time), and stands in for the ones Wallpaper Engine ships itself.
final class TextureStore {
    let device: any MTLDevice
    let item: ItemFiles
    private var cache: [String: GPUTexture?] = [:]
    private var samplers: [String: any MTLSamplerState] = [:]
    /// Mipmaps to generate in the next command buffer (load has no queue of its own).
    private(set) var pendingMipmaps: [any MTLTexture] = []
    private(set) var notes: [String] = []

    lazy var white = solid([255, 255, 255, 255])
    lazy var black = solid([0, 0, 0, 255])

    init(device: any MTLDevice, item: ItemFiles) {
        self.device = device
        self.item = item
    }

    func texture(named name: String) -> GPUTexture? {
        if let hit = cache[name] { return hit }
        var result: GPUTexture?
        if let data = item.data(SceneDocument.texturePath(name)) {
            do { result = try upload(TexFile(data: data)) } catch { notes.append("texture \(name): \(error)") }
        } else if let standIn = builtinStandIn(name) {
            notes.append("texture \(name) ships with Wallpaper Engine, not the item: procedural stand-in")
            result = standIn
        } else {
            notes.append("texture \(name) is missing")
        }
        cache[name] = result
        return result
    }

    func encodePendingWork(_ commandBuffer: any MTLCommandBuffer) {
        guard !pendingMipmaps.isEmpty, let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        for t in pendingMipmaps { blit.generateMipmaps(for: t) }
        blit.endEncoding()
        pendingMipmaps = []
    }

    func sampler(point: Bool, clamp: Bool) -> any MTLSamplerState {
        let key = "\(point)\(clamp)"
        if let s = samplers[key] { return s }
        let d = MTLSamplerDescriptor()
        d.minFilter = point ? .nearest : .linear
        d.magFilter = point ? .nearest : .linear
        d.mipFilter = point ? .notMipmapped : .linear
        d.sAddressMode = clamp ? .clampToEdge : .repeat
        d.tAddressMode = clamp ? .clampToEdge : .repeat
        let s = device.makeSamplerState(descriptor: d)!
        samplers[key] = s
        return s
    }

    private func upload(_ tex: TexFile) throws -> GPUTexture {
        if tex.isVideo { throw ReadError("an MP4 video texture (not decoded by S9)") }
        var textures: [any MTLTexture] = []
        var resolution = SIMD4<Float>(1, 1, 1, 1)
        for image in 0..<tex.images.count {
            let px = try tex.pixels(image: image, mip: 0)
            let format: MTLPixelFormat = switch px.bytesPerPixel {
            case 1: .r8Unorm
            case 2: .rg8Unorm
            default: .rgba8Unorm
            }
            let mipmapped = tex.images[image].count > 1
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: px.width, height: px.height,
                                                             mipmapped: mipmapped)
            d.usage = [.shaderRead]
            d.storageMode = .shared
            guard let t = device.makeTexture(descriptor: d) else { throw ReadError("makeTexture failed") }
            px.bytes.withUnsafeBytes { raw in
                t.replace(region: MTLRegionMake2D(0, 0, px.width, px.height), mipmapLevel: 0,
                          withBytes: raw.baseAddress!, bytesPerRow: px.width * px.bytesPerPixel)
            }
            if mipmapped { pendingMipmaps.append(t) }
            textures.append(t)
            if image == 0 {
                resolution = SIMD4(Float(px.width), Float(px.height),
                                   Float(min(tex.imageWidth, px.width)), Float(min(tex.imageHeight, px.height)))
            }
        }
        return GPUTexture(textures: textures, resolution: resolution, frames: tex.frames,
                          pointFiltered: tex.pointFiltered, clamp: tex.clampUV)
    }

    // MARK: Stand-ins for Wallpaper Engine's own textures

    private func solid(_ rgba: [UInt8]) -> GPUTexture {
        make(1, 1, rgba, clamp: true)
    }

    private func make(_ w: Int, _ h: Int, _ rgba: [UInt8], clamp: Bool) -> GPUTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        d.storageMode = .shared
        let t = device.makeTexture(descriptor: d)!
        t.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: rgba, bytesPerRow: w * 4)
        return GPUTexture(textures: [t], resolution: SIMD4(Float(w), Float(h), Float(w), Float(h)), clamp: clamp)
    }

    /// `util/*` and `particle/*` textures are Wallpaper Engine's; the product would draw its own set.
    private func builtinStandIn(_ name: String) -> GPUTexture? {
        switch name {
        case "util/white": return white
        case "util/black": return black
        case "util/noise": return whiteNoise(256)
        // A flow map with no flow: waterflow reads (rg * 2 - 1) as a direction.
        case "util/noflow": return solid([128, 128, 0, 255])
        case "util/clouds_256": return noise(256, octaves: 5)
        default:
            guard name.hasPrefix("particle/") else { return nil }
            let lower = name.lowercased()
            if lower.contains("fog") || lower.contains("smoke") || lower.contains("cloud") { return blob(128, noisy: true) }
            if lower.contains("shaft") || lower.contains("beam") { return beam(128) }
            return blob(64, noisy: false)
        }
    }

    /// Film grain samples it per pixel: independent random texels.
    private func whiteNoise(_ n: Int) -> GPUTexture {
        var rng = UInt64(0x2545F4914F6CDD1D)
        var px = [UInt8](repeating: 0, count: n * n * 4)
        for i in px.indices {
            rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
            px[i] = UInt8(truncatingIfNeeded: rng >> 32)
        }
        return make(n, n, px, clamp: false)
    }

    private func noise(_ n: Int, octaves: Int) -> GPUTexture {
        var rng = UInt64(0x9E3779B97F4A7C15)
        func rand() -> Float {
            rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
            return Float(rng >> 40) / Float(1 << 24)
        }
        // Value noise on a repeating lattice, summed over octaves.
        var lattices: [[Float]] = []
        for o in 0..<octaves {
            let cells = 4 << o
            lattices.append((0..<(cells * cells * 4)).map { _ in rand() })
        }
        var px = [UInt8](repeating: 0, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                for c in 0..<4 {
                    var v: Float = 0, amp: Float = 0.5, total: Float = 0
                    for o in 0..<octaves {
                        let cells = 4 << o
                        let fx = Float(x) / Float(n) * Float(cells), fy = Float(y) / Float(n) * Float(cells)
                        let x0 = Int(fx) % cells, y0 = Int(fy) % cells
                        let x1 = (x0 + 1) % cells, y1 = (y0 + 1) % cells
                        let tx = fx - Float(Int(fx)), ty = fy - Float(Int(fy))
                        let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty)
                        let l = lattices[o]
                        func at(_ i: Int, _ j: Int) -> Float { l[(j * cells + i) * 4 + c] }
                        let a = at(x0, y0) + (at(x1, y0) - at(x0, y0)) * sx
                        let b = at(x0, y1) + (at(x1, y1) - at(x0, y1)) * sx
                        v += (a + (b - a) * sy) * amp
                        total += amp
                        amp *= 0.5
                    }
                    px[(y * n + x) * 4 + c] = UInt8(max(0, min(255, v / total * 255)))
                }
            }
        }
        return make(n, n, px, clamp: false)
    }

    private func blob(_ n: Int, noisy: Bool) -> GPUTexture {
        var px = [UInt8](repeating: 0, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                let dx = (Float(x) + 0.5) / Float(n) * 2 - 1, dy = (Float(y) + 0.5) / Float(n) * 2 - 1
                var a = max(0, 1 - (dx * dx + dy * dy).squareRoot())
                a *= a
                if noisy { a *= 0.75 + 0.25 * sin(Float(x) * 0.31 + sin(Float(y) * 0.23) * 3) }
                let i = (y * n + x) * 4
                px[i] = 255; px[i + 1] = 255; px[i + 2] = 255
                px[i + 3] = UInt8(max(0, min(255, a * 255)))
            }
        }
        return make(n, n, px, clamp: true)
    }

    private func beam(_ n: Int) -> GPUTexture {
        var px = [UInt8](repeating: 0, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                let dx = abs((Float(x) + 0.5) / Float(n) * 2 - 1)
                let fy = (Float(y) + 0.5) / Float(n)
                let a = max(0, 1 - dx) * max(0, 1 - dx) * sin(fy * .pi)
                let i = (y * n + x) * 4
                px[i] = 255; px[i + 1] = 255; px[i + 2] = 255
                px[i + 3] = UInt8(max(0, min(255, a * 255)))
            }
        }
        return make(n, n, px, clamp: true)
    }
}
