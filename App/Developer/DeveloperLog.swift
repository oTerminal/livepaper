import Foundation
import LivepaperCore

/// The wording of the developer menu's log lines, under `LivepaperSystem.logSubsystem`,
/// category `developer`. The checks on screen are read against them.
nonisolated enum DeveloperLog {
    static let category = "developer"

    static func wallpaperSet(_ wallpaper: WallpaperID, on display: DisplayIdentity, generation: UInt64) -> String {
        "developer: wallpaper \(wallpaper) set on display \(display), generation \(generation)"
    }

    static func fit(_ fit: FitMode, generation: UInt64) -> String {
        "developer: fit \(fit.rawValue) on every display, generation \(generation)"
    }

    static func focalPoint(_ point: Point, generation: UInt64) -> String {
        "developer: focal point (\(point.x), \(point.y)) on every display, generation \(generation)"
    }

    static func volume(_ volume: Double, generation: UInt64) -> String {
        "developer: volume \(volume) on every display, generation \(generation)"
    }

    static func pauseAll(generation: UInt64) -> String {
        "developer: pause all, generation \(generation)"
    }

    static func resume(generation: UInt64) -> String {
        "developer: resume, generation \(generation)"
    }

    static func importFinished(_ wallpaper: Wallpaper) -> String {
        "developer: import finished, wallpaper \(wallpaper.id) \"\(wallpaper.name)\""
    }

    static func importDuplicate(of wallpaper: Wallpaper) -> String {
        "developer: import finished, duplicate of wallpaper \(wallpaper.id) \"\(wallpaper.name)\""
    }

    static func importFailed(_ file: String, _ error: any Error) -> String {
        "developer: import failed for \"\(file)\": \(error)"
    }

    static func checkStarted(_ check: DeveloperCheck) -> String {
        "developer: check \(check.rawValue) started"
    }

    static func checkEnded(_ check: DeveloperCheck, last: WallpaperID?, generation: UInt64) -> String {
        "developer: check \(check.rawValue) ended on wallpaper \(last?.description ?? "none"), generation \(generation)"
    }

    static func swept(_ count: Int) -> String {
        "developer: swept \(count) interrupted imports"
    }

    static func sweepFailed(_ error: any Error) -> String {
        "developer: sweeping interrupted imports failed: \(error)"
    }

    static func libraryUnreadable(_ error: any Error) -> String {
        "developer: library not read: \(error)"
    }

    static func restored(_ count: Int, generation: UInt64) -> String {
        "developer: restored \(count) displays from render state \(generation)"
    }

    static func renderStateUnreadable(_ error: any Error) -> String {
        "developer: render state on disk not read: \(error)"
    }

    static func activationFailed(_ error: any Error) -> String {
        "developer: host not activated: \(error)"
    }

    static func quit(stopped generation: UInt64?) -> String {
        guard let generation else { return "developer: quit, no render state stopped" }
        return "developer: quit, render state \(generation) stopped"
    }
}
