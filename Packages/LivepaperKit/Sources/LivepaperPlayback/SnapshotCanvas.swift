import CoreGraphics
import CoreVideo
import IOSurface
import LivepaperCore
import VideoToolbox

/// Where the picture goes in a snapshot: the surface's size and the picture's rectangle, both
/// in pixels, the rectangle from Core's `pictureRect` (y grows downwards).
public struct SnapshotLayout: Equatable, Sendable {
    public var surface: Size
    public var picture: Rect

    public init(surface: Size, picture: Rect) {
        self.surface = surface
        self.picture = picture
    }
}

/// The picture WallpaperAgent shows while no live context is hosted (S6, by construction):
/// what is on screen, cropped as the layer shows it, at the surface's pixel size, in BGRA.
enum SnapshotCanvas {
    /// The decoder's pictures are in a compressed pixel format that cannot be read directly
    /// (`Spikes/results/S2.md`), so the picture goes through a BGRA buffer first.
    static func image(of picture: CVPixelBuffer) -> CGImage? {
        var session: VTPixelTransferSession?
        VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &session)
        guard let session else { return nil }
        defer { VTPixelTransferSessionInvalidate(session) }
        guard let bgra = makeBuffer(width: CVPixelBufferGetWidth(picture), height: CVPixelBufferGetHeight(picture)),
              VTPixelTransferSessionTransferImage(session, from: picture, to: bgra) == noErr else { return nil }
        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(bgra, options: nil, imageOut: &image)
        return image
    }

    /// `image` drawn where the layer shows it, over black, as Fit's bars are.
    static func render(_ image: CGImage, _ layout: SnapshotLayout) -> IOSurface? {
        let width = Int(layout.surface.width.rounded())
        let height = Int(layout.surface.height.rounded())
        guard width > 0, height > 0, let buffer = makeBuffer(width: width, height: height),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .high
        context.draw(image, in: flipped(layout.picture, within: Double(height)))
        return CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue()
    }

    private static func makeBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes, &buffer)
        return buffer
    }
}
