import Foundation
import LivepaperCore

// Readable, fixed identifiers: wallpaper 1 is always the same wallpaper.
private func numberedUUID(_ prefix: String, _ number: Int) -> UUID {
    let digits = String(number)
    let padded = String(repeating: "0", count: 12 - digits.count) + digits
    guard let uuid = UUID(uuidString: "\(prefix)-0000-0000-0000-\(padded)") else {
        preconditionFailure("not a UUID: \(prefix), \(number)")
    }
    return uuid
}

extension WallpaperID {
    static func numbered(_ number: Int) -> WallpaperID {
        WallpaperID(uuid: numberedUUID("AAAAAAAA", number))
    }
}

extension PlaylistID {
    static func numbered(_ number: Int) -> PlaylistID {
        PlaylistID(uuid: numberedUUID("BBBBBBBB", number))
    }
}

extension DisplayIdentity {
    static func numbered(_ number: Int) -> DisplayIdentity {
        DisplayIdentity(uuid: numberedUUID("DDDDDDDD", number))
    }
}
