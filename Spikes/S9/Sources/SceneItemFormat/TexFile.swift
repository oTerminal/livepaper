import Compression
import Foundation
import ImageIO

/// A Wallpaper Engine `.tex`, as learned from the samples:
///
///     "TEXV0005\0" "TEXI0001\0"
///     i32 format, i32 flags, i32 textureWidth, i32 textureHeight, i32 imageWidth, i32 imageHeight, u32 (unknown)
///     "TEXB000n\0" i32 imageCount
///        n >= 3: i32 freeImageFormat (-1 raw, 2 JPEG, 13 PNG)
///        n >= 4: i32 (0 in every sample; guessed to be an "is mp4" flag)
///        per image: i32 mipCount; per mip: i32 w, i32 h, [n >= 2: i32 lz4, i32 decompressedSize], i32 size, bytes
///     optional "TEXS000n\0" i32 frameCount, [n >= 3: i32 frameWidth, i32 frameHeight],
///        per frame: i32 imageIndex, f32 seconds, f32 x, f32 y, f32 ux, f32 uy, f32 vx, f32 vy
public struct TexFile: Sendable {
    public enum Format: Int32, Sendable {
        case rgba8888 = 0
        case rg88 = 8
        case r8 = 9
    }

    public struct Mip: Sendable {
        public let width: Int
        public let height: Int
        public let lz4: Bool
        public let decompressedSize: Int
        public let payload: Data
    }

    public struct Frame: Sendable {
        public let image: Int
        public let seconds: Float
        public let x, y, ux, uy, vx, vy: Float
    }

    public let formatCode: Int32
    public let flags: UInt32
    public let textureWidth, textureHeight, imageWidth, imageHeight: Int
    public let containerVersion: String
    public let freeImageFormat: Int32
    public let images: [[Mip]]
    public let frames: [Frame]
    public let frameWidth, frameHeight: Int

    public var format: Format? { Format(rawValue: formatCode) }
    /// Inferred from the samples: 0x1 on the point-filtered GIF, 0x2 on nearly everything that should not
    /// repeat, 0x4 on the two animated textures, 0x20 on the one whose payload is an MP4.
    public var pointFiltered: Bool { flags & 0x1 != 0 }
    public var clampUV: Bool { flags & 0x2 != 0 }
    public var isAnimated: Bool { !frames.isEmpty }
    public var isVideo: Bool { flags & 0x20 != 0 }

    public init(data: Data) throws {
        var r = ByteReader(data)
        let v = try r.magic()
        guard v.hasPrefix("TEXV") else { throw ReadError("not a tex: \(v)") }
        let i = try r.magic()
        guard i.hasPrefix("TEXI") else { throw ReadError("expected TEXI, got \(i)") }
        formatCode = try r.i32()
        flags = try r.u32()
        textureWidth = try r.int()
        textureHeight = try r.int()
        imageWidth = try r.int()
        imageHeight = try r.int()
        _ = try r.u32()
        containerVersion = try r.magic()
        guard containerVersion.hasPrefix("TEXB"), let n = Int(containerVersion.dropFirst(4)) else {
            throw ReadError("expected TEXB, got \(containerVersion)")
        }
        guard (1...4).contains(n) else { throw ReadError("unknown container \(containerVersion)") }
        let imageCount = try r.int()
        freeImageFormat = n >= 3 ? try r.i32() : -1
        if n >= 4 { _ = try r.i32() }
        var images: [[Mip]] = []
        for _ in 0..<imageCount {
            let mipCount = try r.int()
            var mips: [Mip] = []
            for _ in 0..<mipCount {
                let w = try r.int(), h = try r.int()
                var lz4 = false, decompressed = 0
                if n >= 2 {
                    lz4 = try r.i32() != 0
                    decompressed = try r.int()
                }
                let size = try r.int()
                mips.append(Mip(width: w, height: h, lz4: lz4, decompressedSize: decompressed, payload: try r.bytes(size)))
            }
            images.append(mips)
        }
        self.images = images
        var frames: [Frame] = []
        var fw = 0, fh = 0
        if r.remaining > 9, let s = try? r.magic(), s.hasPrefix("TEXS"), let sv = Int(s.dropFirst(4)) {
            let count = try r.int()
            if sv >= 3 {
                fw = try r.int()
                fh = try r.int()
            }
            for _ in 0..<count {
                frames.append(Frame(image: try r.int(), seconds: try r.f32(), x: try r.f32(), y: try r.f32(),
                                    ux: try r.f32(), uy: try r.f32(), vx: try r.f32(), vy: try r.f32()))
            }
        }
        self.frames = frames
        frameWidth = fw
        frameHeight = fh
    }

    public var payloadKind: String {
        if isVideo { return "mp4" }
        switch freeImageFormat {
        case -1: return "raw"
        case 2: return "jpeg"
        case 13: return "png"
        default: return "freeimage\(freeImageFormat)"
        }
    }

    public struct Pixels: Sendable {
        public let width: Int
        public let height: Int
        public let bytesPerPixel: Int
        public let bytes: Data
    }

    /// Decoded pixels of one mip: RGBA8 for embedded images, else as stored (RGBA8, RG8 or R8).
    public func pixels(image: Int = 0, mip: Int = 0) throws -> Pixels {
        let m = images[image][mip]
        if isVideo { throw ReadError("payload is an MP4 video") }
        if freeImageFormat != -1 {
            return try Self.decodeImage(m.payload)
        }
        guard let format else { throw ReadError("unknown raw format \(formatCode)") }
        let bpp = switch format {
        case .rgba8888: 4
        case .rg88: 2
        case .r8: 1
        }
        let expected = m.width * m.height * bpp
        let raw: Data
        if m.lz4 {
            raw = try Self.lz4(m.payload, size: m.decompressedSize)
        } else {
            raw = m.payload
        }
        guard raw.count >= expected else { throw ReadError("mip is \(raw.count) bytes, want \(expected)") }
        return Pixels(width: m.width, height: m.height, bytesPerPixel: bpp, bytes: raw.prefix(expected))
    }

    static func lz4(_ input: Data, size: Int) throws -> Data {
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { out in
            input.withUnsafeBytes { inp in
                compression_decode_buffer(out.bindMemory(to: UInt8.self).baseAddress!, size,
                                          inp.bindMemory(to: UInt8.self).baseAddress!, input.count,
                                          nil, COMPRESSION_LZ4_RAW)
            }
        }
        guard written == size else { throw ReadError("lz4 gave \(written) of \(size) bytes") }
        return output
    }

    /// PNG or JPEG to straight-alpha RGBA8.
    static func decodeImage(_ data: Data) throws -> Pixels {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw ReadError("ImageIO could not decode the embedded image")
        }
        let w = image.width, h = image.height
        var bytes = Data(count: w * h * 4)
        try bytes.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw ReadError("no CGContext")
            }
            ctx.setBlendMode(.copy)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            // Undo the premultiplication CoreGraphics insists on.
            let p = buf.bindMemory(to: UInt8.self)
            if image.alphaInfo != .none, image.alphaInfo != .noneSkipLast, image.alphaInfo != .noneSkipFirst {
                for i in stride(from: 0, to: w * h * 4, by: 4) {
                    let a = Int(p[i + 3])
                    if a != 0, a != 255 {
                        p[i] = UInt8(min(255, Int(p[i]) * 255 / a))
                        p[i + 1] = UInt8(min(255, Int(p[i + 1]) * 255 / a))
                        p[i + 2] = UInt8(min(255, Int(p[i + 2]) * 255 / a))
                    }
                }
            }
        }
        return Pixels(width: w, height: h, bytesPerPixel: 4, bytes: bytes)
    }
}
