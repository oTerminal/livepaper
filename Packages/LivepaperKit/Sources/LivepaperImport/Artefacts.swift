import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ArtefactError: Error, Equatable, Sendable {
    case noPicture
    case posterNotWritten
}

/// Writes the poster: the first frame that is not black, at the picture's own
/// size. A video that fades in from black would otherwise sit in the library,
/// and on the desktop when playback is stopped (record 0003), as a black tile.
@concurrent
func makePoster(of optimisedCopy: URL, at destination: URL) async throws {
    let asset = AVURLAsset(url: optimisedCopy)
    let duration = try await asset.load(.duration).seconds
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero

    // Looked for a quarter of a second at a time, and not for ever: a video that is dark throughout keeps its first frame.
    let times = stride(from: 0, to: min(duration, 20), by: 0.25).map { CMTime(seconds: $0, preferredTimescale: 600) }
    var first: CGImage?
    var poster: CGImage?
    for time in times {
        try Task.checkCancellation()
        guard let image = try? await generator.image(at: time).image else { continue }
        first = first ?? image
        if !image.isBlack {
            poster = image
            break
        }
    }

    guard let image = poster ?? first else { throw ArtefactError.noPicture }
    guard let file = CGImageDestinationCreateWithURL(destination as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
        throw ArtefactError.posterNotWritten
    }
    CGImageDestinationAddImage(file, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
    guard CGImageDestinationFinalize(file) else { throw ArtefactError.posterNotWritten }
}

extension CGImage {
    /// Black, or as good as: nothing in the picture, scaled down to a few hundred pixels, is brighter than a dark grey.
    var isBlack: Bool {
        let (width, height) = (32, 18)
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .low
            context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn && (pixels.max() ?? 0) < 32
    }
}
