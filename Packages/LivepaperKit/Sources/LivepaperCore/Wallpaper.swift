import Foundation

/// The SHA-256 of a source file, taken before any conversion. Two imports of
/// the same bytes have the same fingerprint, whatever the files are called.
public struct Fingerprint: Hashable, Codable, Sendable, CustomStringConvertible {
    /// 64 lowercase hex digits.
    public let sha256: String

    public init(sha256: String) {
        self.sha256 = sha256.lowercased()
    }

    // Persisted as a bare string.
    public init(from decoder: any Decoder) throws {
        self.init(sha256: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(sha256)
    }

    public var description: String { sha256 }
}

/// What the file details panel shows about a wallpaper's optimised copy.
public struct WallpaperDetails: Codable, Equatable, Sendable {
    /// In seconds.
    public var duration: Double
    /// In pixels.
    public var width: Int
    public var height: Int
    public var frameRate: Double
    public var codec: String
    public var byteCount: Int

    public init(duration: Double, width: Int, height: Int, frameRate: Double, codec: String, byteCount: Int) {
        self.duration = duration
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.codec = codec
        self.byteCount = byteCount
    }
}

/// A looping video in the library that can be shown on a display.
///
/// Its files are named by paths relative to the library root, which go
/// through `LibraryLocation.resolve` before anything is opened.
public struct Wallpaper: Codable, Equatable, Identifiable, Sendable {
    public let id: WallpaperID
    public var name: String
    public var isFavourite: Bool
    public let addedAt: Date
    public var fingerprint: Fingerprint
    public var optimisedCopy: String
    public var poster: String
    public var hoverPreview: String?
    public var details: WallpaperDetails
    public var presentation: Presentation
    /// 0 to 1. Wallpapers are imported silent.
    public var volume: Double

    public init(
        id: WallpaperID,
        name: String,
        isFavourite: Bool = false,
        addedAt: Date,
        fingerprint: Fingerprint,
        optimisedCopy: String,
        poster: String,
        hoverPreview: String? = nil,
        details: WallpaperDetails,
        presentation: Presentation = Presentation(),
        volume: Double = 0
    ) {
        self.id = id
        self.name = name
        self.isFavourite = isFavourite
        self.addedAt = addedAt
        self.fingerprint = fingerprint
        self.optimisedCopy = optimisedCopy
        self.poster = poster
        self.hoverPreview = hoverPreview
        self.details = details
        self.presentation = presentation
        self.volume = volume
    }
}
