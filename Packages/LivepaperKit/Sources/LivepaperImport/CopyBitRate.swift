import AVFoundation
import Foundation

extension VideoProbe {
    /// The most an optimised copy's video may spend, in bits per second: an
    /// H.264 source's own rate, which the remux the transcode stands in for
    /// would have kept. Nil for the rest, which keep a constant quality: an
    /// HEVC file at its own rate loses visibly to the hardware encoder, and
    /// the rate of ProRes and the like says nothing about what the picture needs.
    var copyBitRateLimit: Double? {
        VideoProbe.keptCodecs[codec] == "h264" && bitRate > 0 ? bitRate : nil
    }
}

/// Transcodes a source file into the optimised copy: at constant quality 0.75,
/// or held to the source's rate where there is a limit (`copyBitRateLimit`).
///
/// The encoder is asked for 95% of the limit, and keeps to it over a minute
/// or more of real footage. On a clip of a few seconds, or a picture drawn by
/// a program, it can overshoot by half again or more, so a copy that comes
/// out over the limit is encoded again with the target scaled down by the
/// miss, twice at most. The last one is kept, whatever it came to.
func transcodeOptimisedCopy(
    _ source: URL, of video: VideoProbe, rate: FrameRate, to destination: URL, progress: @escaping @Sendable (Double) -> Void
) async throws {
    guard let limit = video.copyBitRateLimit else {
        try await transcode(source, to: destination, as: .optimisedCopy(rate: rate, spending: .quality(0.75)), progress: progress)
        return
    }
    let aim = 0.95 * limit
    var target = aim
    for attempt in 1...3 {
        let rendition = Rendition.optimisedCopy(rate: rate, spending: .averageBitRate(Int(target)))
        try await transcode(source, to: destination, as: rendition, progress: progress)
        let achieved = try await videoBitRate(of: destination)
        if achieved <= limit || attempt == 3 { return }
        try FileManager.default.removeItem(at: destination)
        target *= aim / achieved
    }
}

/// The average rate of a movie file's video samples, in bits per second.
func videoBitRate(of url: URL) async throws -> Double {
    guard let track = try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first else { throw MediaError.noVideoTrack }
    return Double(try await track.load(.estimatedDataRate))
}
